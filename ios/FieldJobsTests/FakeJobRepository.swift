import Domain
import Foundation

/// Yields its snapshots in order, then finishes, so `start()` returns once the screen has shown them.
final class FakeJobRepository: JobRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshotsToYield: [JobsSnapshot]
    private let refreshError: (any Error)?
    private let photo: Data?
    private let holdsComplete: Bool
    private var completeGate: CheckedContinuation<Void, Never>?
    private var _calls: [String] = []

    /// `photo` is the stored photo for every job; `holdsComplete` makes `complete` wait for `releaseComplete()`.
    init(snapshots: [JobsSnapshot] = [JobsSnapshot(jobs: [], updatedAt: nil, isOnline: true, sendingBlocked: false)],
         refreshError: (any Error)? = nil, photo: Data? = nil, holdsComplete: Bool = false) {
        snapshotsToYield = snapshots
        self.refreshError = refreshError
        self.photo = photo
        self.holdsComplete = holdsComplete
    }

    /// "refresh", "sendPending", "savePhoto(id)", "saveNote(id, note)" and "complete(id)", in the order they were called.
    var calls: [String] { lock.withLock { _calls } }

    func snapshots() -> AsyncStream<JobsSnapshot> {
        let snapshots = snapshotsToYield
        return AsyncStream { continuation in
            snapshots.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
    func refresh() async throws {
        record("refresh")
        if let refreshError { throw refreshError }
    }
    func job(id: String) async throws -> Job? { snapshotsToYield.last?.jobs.first { $0.id == id } }
    func photoData(jobID: String) async throws -> Data? { photo }
    func savePhoto(jobID: String, jpeg: Data) async throws { record("savePhoto(\(jobID))") }
    /// Slow, like a disk write, so a caller that doesn't wait for the save is caught.
    func saveNote(jobID: String, note: String?) async throws {
        try? await Task.sleep(nanoseconds: 20_000_000)
        record("saveNote(\(jobID), \(note ?? "nil"))")
    }
    func complete(jobID: String, completedAt: Date) async throws {
        guard holdsComplete else { return record("complete(\(jobID))") }
        await withCheckedContinuation { continuation in
            lock.withLock {
                _calls.append("complete(\(jobID))")
                // Only the first call is held, so a second call shows up in `calls` instead of hanging the test.
                if completeGate == nil { completeGate = continuation } else { continuation.resume() }
            }
        }
    }
    func sendPending() async { record("sendPending") }

    /// Lets a held `complete` return.
    func releaseComplete() { lock.withLock { completeGate }?.resume() }

    private func record(_ call: String) { lock.withLock { _calls.append(call) } }
}
