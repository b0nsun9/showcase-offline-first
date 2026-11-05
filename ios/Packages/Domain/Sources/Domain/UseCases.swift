import Foundation

public struct LoadJobs: Sendable {
    let repository: any JobRepository
    public init(repository: any JobRepository) { self.repository = repository }

    public func snapshots() -> AsyncStream<JobsSnapshot> { repository.snapshots() }
    public func refresh() async throws { try await repository.refresh() }
    public func photo(jobID: String) async throws -> Data? { try await repository.photoData(jobID: jobID) }
}

public struct AttachPhoto: Sendable {
    let repository: any JobRepository
    public init(repository: any JobRepository) { self.repository = repository }

    public func callAsFunction(jobID: String, jpeg: Data) async throws {
        guard let job = try await repository.job(id: jobID) else { throw JobError.unknownJob }
        guard job.photo == nil else { throw JobError.photoAlreadyTaken }
        guard jpeg.count <= Job.photoByteLimit else { throw JobError.photoTooLarge }
        try await repository.savePhoto(jobID: jobID, jpeg: jpeg)
    }
}

public struct SaveNote: Sendable {
    let repository: any JobRepository
    public init(repository: any JobRepository) { self.repository = repository }

    public func callAsFunction(jobID: String, note: String) async throws {
        guard note.utf16.count <= Job.noteLimit else { throw JobError.noteTooLong }
        try await repository.saveNote(jobID: jobID, note: note.isEmpty ? nil : note)
    }
}

public struct CompleteJob: Sendable {
    let repository: any JobRepository
    let now: @Sendable () -> Date
    public init(repository: any JobRepository, now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    public func callAsFunction(jobID: String) async throws {
        guard let job = try await repository.job(id: jobID) else { throw JobError.unknownJob }
        guard job.completedAt == nil else { throw JobError.alreadyCompleted }
        guard job.photo != nil else { throw JobError.photoMissing }
        try await repository.complete(jobID: jobID, completedAt: now())
    }
}

public struct SendPendingWork: Sendable {
    let repository: any JobRepository
    public init(repository: any JobRepository) { self.repository = repository }

    public func callAsFunction() async { await repository.sendPending() }
}
