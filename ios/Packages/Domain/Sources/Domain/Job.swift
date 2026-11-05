import Foundation

public struct Job: Equatable, Sendable, Identifiable {
    public let id: String
    public let address: String
    public let task: String
    public let windowStart: String
    public let windowEnd: String
    public var photo: PhotoInfo?
    public var note: String?
    public var completedAt: Date?
    public var sync: SyncState

    public static let noteLimit = 1000
    public static let photoByteLimit = 5_242_880

    public init(
        id: String, address: String, task: String, windowStart: String, windowEnd: String,
        photo: PhotoInfo? = nil, note: String? = nil, completedAt: Date? = nil, sync: SyncState = .notCompleted
    ) {
        self.id = id
        self.address = address
        self.task = task
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.photo = photo
        self.note = note
        self.completedAt = completedAt
        self.sync = sync
    }
}

public struct PhotoInfo: Equatable, Sendable {
    public let bytes: Int
    public let sha256: String

    public init(bytes: Int, sha256: String) {
        self.bytes = bytes
        self.sha256 = sha256
    }
}

public enum SyncState: Equatable, Sendable { case notCompleted, waiting, sent, couldNotSend }

public struct JobsSnapshot: Equatable, Sendable {
    public var jobs: [Job]
    public var updatedAt: Date?
    public var isOnline: Bool
    public var sendingBlocked: Bool

    public init(jobs: [Job], updatedAt: Date?, isOnline: Bool, sendingBlocked: Bool) {
        self.jobs = jobs
        self.updatedAt = updatedAt
        self.isOnline = isOnline
        self.sendingBlocked = sendingBlocked
    }
}

public enum JobError: Error, Equatable {
    case unknownJob, photoMissing, photoAlreadyTaken, photoTooLarge, noteTooLong, alreadyCompleted
}
