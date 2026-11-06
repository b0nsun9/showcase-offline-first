import Domain
import Foundation

/// Yields its snapshots in order, then finishes, so `start()` returns once the screen has shown them.
final class FakeJobRepository: JobRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshotsToYield: [JobsSnapshot]
    private let refreshError: (any Error)?
    private var _calls: [String] = []

    init(snapshots: [JobsSnapshot] = [JobsSnapshot(jobs: [], updatedAt: nil, isOnline: true, sendingBlocked: false)],
         refreshError: (any Error)? = nil) {
        snapshotsToYield = snapshots
        self.refreshError = refreshError
    }

    /// "refresh" and "sendPending", in the order they were called.
    var calls: [String] { lock.withLock { _calls } }

    func snapshots() -> AsyncStream<JobsSnapshot> {
        let snapshots = snapshotsToYield
        return AsyncStream { continuation in
            snapshots.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
    func refresh() async throws {
        lock.withLock { _calls.append("refresh") }
        if let refreshError { throw refreshError }
    }
    func job(id: String) async throws -> Job? { nil }
    func photoData(jobID: String) async throws -> Data? { nil }
    func savePhoto(jobID: String, jpeg: Data) async throws {}
    func saveNote(jobID: String, note: String?) async throws {}
    func complete(jobID: String, completedAt: Date) async throws {}
    func sendPending() async { lock.withLock { _calls.append("sendPending") } }
}
