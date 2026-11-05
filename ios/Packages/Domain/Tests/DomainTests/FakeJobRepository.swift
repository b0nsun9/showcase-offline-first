import Domain
import Foundation

final class FakeJobRepository: JobRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [String: Job]
    private var _completeCalls: [(String, Date)] = []
    private var _noteCalls: [(String, String?)] = []
    private var _photoCalls: [String] = []

    init(jobs: [Job] = []) { self.jobs = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) }) }

    var completeCalls: [(String, Date)] { lock.withLock { _completeCalls } }
    var noteCalls: [(String, String?)] { lock.withLock { _noteCalls } }
    var photoCalls: [String] { lock.withLock { _photoCalls } }

    func snapshots() -> AsyncStream<JobsSnapshot> {
        let snapshot = JobsSnapshot(jobs: lock.withLock { Array(jobs.values) }, updatedAt: nil, isOnline: true, sendingBlocked: false)
        return AsyncStream { $0.yield(snapshot); $0.finish() }
    }
    func refresh() async throws {}
    func job(id: String) async throws -> Job? { lock.withLock { jobs[id] } }
    func photoData(jobID: String) async throws -> Data? { nil }
    func savePhoto(jobID: String, jpeg: Data) async throws { lock.withLock { _photoCalls.append(jobID) } }
    func saveNote(jobID: String, note: String?) async throws { lock.withLock { _noteCalls.append((jobID, note)) } }
    func complete(jobID: String, completedAt: Date) async throws { lock.withLock { _completeCalls.append((jobID, completedAt)) } }
    func sendPending() async {}
}

extension Job {
    static func make(
        id: String = "job-1", address: String = "1 Main St", task: String = "Fix", windowStart: String = "08:00",
        windowEnd: String = "10:00", photo: PhotoInfo? = nil, note: String? = nil, completedAt: Date? = nil,
        sync: SyncState = .notCompleted
    ) -> Job {
        Job(id: id, address: address, task: task, windowStart: windowStart, windowEnd: windowEnd,
            photo: photo, note: note, completedAt: completedAt, sync: sync)
    }
}

let somePhoto = PhotoInfo(bytes: 10, sha256: "abc")
