import Foundation

public protocol JobRepository: Sendable {
    /// Yields the current state at once, then after every change.
    func snapshots() -> AsyncStream<JobsSnapshot>
    func refresh() async throws
    func job(id: String) async throws -> Job?
    func photoData(jobID: String) async throws -> Data?
    func savePhoto(jobID: String, jpeg: Data) async throws
    func saveNote(jobID: String, note: String?) async throws
    /// One atomic save.
    func complete(jobID: String, completedAt: Date) async throws
    /// One pass over due items; outcomes land in `snapshots()`.
    func sendPending() async
}
