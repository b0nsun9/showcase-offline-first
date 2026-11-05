import CoreData
import CryptoKit
import Domain
import Foundation

struct OutboxItem: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case complete(idempotencyKey: String, body: Data), photo }
    let id: UUID
    let jobID: String
    let kind: Kind
    let sequence: Int64
    var attempts: Int
    var nextAttemptAt: Date?
    var photoMismatches: Int
}

final class JobStore: @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let lock = NSLock()
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// `nil` opens an in-memory store.
    init(storeURL: URL?) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: StoreModel.shared)
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil,
            at: storeURL ?? URL(fileURLWithPath: "/dev/null"),
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
    }

    var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            let key = UUID()
            lock.lock(); listeners[key] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.listeners[key] = nil; self?.lock.unlock()
            }
        }
    }

    // MARK: Reads

    func jobs() async throws -> [Job] {
        try await context.perform { [self] in try loadJobs() }
    }

    func photoData(jobID: String) async throws -> Data? {
        try await context.perform { [self] in try fetchJob(jobID)?.value(forKey: "photo") as? Data }
    }

    func dueItems(now: Date) async throws -> [OutboxItem] {
        try await context.perform { [self] in
            let request = outboxRequest("failed == NO AND (nextAttemptAt == nil OR nextAttemptAt <= %@)", now as NSDate)
            return try context.fetch(request).map(item)
        }
    }

    func earliestWait() async throws -> Date? {
        try await context.perform { [self] in
            let request = outboxRequest("failed == NO AND nextAttemptAt != nil")
            return try context.fetch(request).compactMap { $0.value(forKey: "nextAttemptAt") as? Date }.min()
        }
    }

    // MARK: Job writes

    func apply(server: [Job]) async throws {
        try await context.perform { [self] in
            let merged = JobMerge.merge(local: try loadJobs(), server: server)
            let serverByID = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let keep = Set(merged.map(\.id))
            for entity in try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "JobEntity")) {
                if !keep.contains(entity.value(forKey: "id") as? String ?? "") { context.delete(entity) }
            }
            for (index, job) in merged.enumerated() {
                let entity = try fetchJob(job.id) ?? NSEntityDescription.insertNewObject(forEntityName: "JobEntity", into: context)
                write(job, position: index, to: entity)
                if let confirmed = serverByID[job.id] { entity.setValue(confirmed.completedAt != nil, forKey: "serverCompleted") }
            }
            try save()
        }
    }

    func savePhoto(jobID: String, jpeg: Data) async throws {
        try await context.perform { [self] in
            guard let entity = try fetchJob(jobID) else { throw JobError.unknownJob }
            guard (entity.value(forKey: "photoBytes") as? Int64 ?? 0) == 0 else { throw JobError.photoAlreadyTaken }
            guard jpeg.count <= Job.photoByteLimit else { throw JobError.photoTooLarge }
            entity.setValue(jpeg, forKey: "photo")
            entity.setValue(Int64(jpeg.count), forKey: "photoBytes")
            entity.setValue(SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined(), forKey: "photoSHA256")
            try save()
        }
    }

    func saveNote(jobID: String, note: String?) async throws {
        try await context.perform { [self] in
            guard let entity = try fetchJob(jobID) else { throw JobError.unknownJob }
            guard entity.value(forKey: "completedAt") == nil else { throw JobError.alreadyCompleted }
            guard (note?.utf16.count ?? 0) <= Job.noteLimit else { throw JobError.noteTooLong }
            entity.setValue(note, forKey: "note")
            try save()
        }
    }

    /// One perform, one save: the job, the frozen body and both queue items land together or not at all.
    func complete(jobID: String, completedAt: Date, idempotencyKey: String) async throws {
        try await context.perform { [self] in
            guard let entity = try fetchJob(jobID) else { throw JobError.unknownJob }
            guard entity.value(forKey: "completedAt") == nil else { throw JobError.alreadyCompleted }
            guard (entity.value(forKey: "photoBytes") as? Int64 ?? 0) > 0 else { throw JobError.photoMissing }
            entity.setValue(completedAt, forKey: "completedAt")
            let body = CompletionBody.encode(completedAt: completedAt, note: entity.value(forKey: "note") as? String)
            let last = try context.fetch(outboxRequest(nil, sort: false, limit: 1, descending: true)).first
            let next = (last?.value(forKey: "sequence") as? Int64 ?? 0) + 1
            for (offset, kind) in ["complete", "photo"].enumerated() {
                let row = NSEntityDescription.insertNewObject(forEntityName: "OutboxEntity", into: context)
                row.setValue(UUID(), forKey: "id")
                row.setValue(jobID, forKey: "jobID")
                row.setValue(kind, forKey: "kind")
                row.setValue(Int64(offset) + next, forKey: "sequence")
                if kind == "complete" {
                    row.setValue(idempotencyKey, forKey: "idempotencyKey")
                    row.setValue(body, forKey: "body")
                }
            }
            try save()
        }
    }

    // MARK: Queue writes

    func finish(_ item: OutboxItem, serverJob: Job?) async throws {
        try await context.perform { [self] in
            if let row = try fetchRow(item.id) { context.delete(row) }
            if let serverJob, let entity = try fetchJob(serverJob.id) {
                write(serverJob, position: Int(entity.value(forKey: "position") as? Int16 ?? 0), to: entity)
                entity.setValue(true, forKey: "serverCompleted")
            }
            try save()
        }
    }

    func reschedule(_ item: OutboxItem, at date: Date, isBackoff: Bool) async throws {
        try await update(item) { row in
            row.setValue((row.value(forKey: "attempts") as? Int32 ?? 0) + 1, forKey: "attempts")
            row.setValue(date, forKey: "nextAttemptAt")
            row.setValue(isBackoff, forKey: "waitIsBackoff")
        }
    }

    func clearBackoffWaits() async throws {
        try await context.perform { [self] in
            for row in try context.fetch(outboxRequest("waitIsBackoff == YES")) {
                row.setValue(nil, forKey: "nextAttemptAt")
                row.setValue(false, forKey: "waitIsBackoff")
            }
            try save()
        }
    }

    func markCouldNotSend(_ item: OutboxItem) async throws {
        try await update(item) { $0.setValue(true, forKey: "failed") }
    }

    func recordPhotoMismatch(_ item: OutboxItem) async throws -> Int {
        try await context.perform { [self] in
            guard let row = try fetchRow(item.id) else { return item.photoMismatches }
            let count = (row.value(forKey: "photoMismatches") as? Int32 ?? 0) + 1
            row.setValue(count, forKey: "photoMismatches")
            try save()
            return Int(count)
        }
    }

    // MARK: Helpers (call only inside `context.perform`)

    private func update(_ item: OutboxItem, _ change: @escaping @Sendable (NSManagedObject) -> Void) async throws {
        try await context.perform { [self] in
            guard let row = try fetchRow(item.id) else { return }
            change(row)
            try save()
        }
    }

    private func save() throws {
        try context.save()
        lock.lock(); let current = Array(listeners.values); lock.unlock()
        current.forEach { $0.yield() }
    }

    private func fetchJob(_ id: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "JobEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchRow(_ id: UUID) throws -> NSManagedObject? {
        let request = outboxRequest("id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func outboxRequest(_ format: String?, _ args: CVarArg..., sort: Bool = true, limit: Int = 0, descending: Bool = false) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "OutboxEntity")
        if let format { request.predicate = NSPredicate(format: format, argumentArray: args) }
        request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: !descending)]
        request.fetchLimit = limit
        return request
    }

    private func loadJobs() throws -> [Job] {
        var states: [String: SyncState] = [:]
        for row in try context.fetch(outboxRequest(nil)) {
            let id = row.value(forKey: "jobID") as? String ?? ""
            if row.value(forKey: "failed") as? Bool == true { states[id] = .couldNotSend }
            else if states[id] == nil { states[id] = .waiting }
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: "JobEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        return try context.fetch(request).map { e in
            let id = e.value(forKey: "id") as? String ?? ""
            let completedAt = e.value(forKey: "completedAt") as? Date
            let bytes = e.value(forKey: "photoBytes") as? Int64 ?? 0
            return Job(
                id: id,
                address: e.value(forKey: "address") as? String ?? "",
                task: e.value(forKey: "task") as? String ?? "",
                windowStart: e.value(forKey: "windowStart") as? String ?? "",
                windowEnd: e.value(forKey: "windowEnd") as? String ?? "",
                photo: bytes > 0 ? PhotoInfo(bytes: Int(bytes), sha256: e.value(forKey: "photoSHA256") as? String ?? "") : nil,
                note: e.value(forKey: "note") as? String,
                completedAt: completedAt,
                sync: completedAt == nil ? .notCompleted : (states[id] ?? .sent))
        }
    }

    /// Writes fields and `PhotoInfo` only; the stored photo bytes are never touched.
    private func write(_ job: Job, position: Int, to e: NSManagedObject) {
        e.setValue(job.id, forKey: "id")
        e.setValue(job.address, forKey: "address")
        e.setValue(job.task, forKey: "task")
        e.setValue(job.windowStart, forKey: "windowStart")
        e.setValue(job.windowEnd, forKey: "windowEnd")
        e.setValue(Int16(position), forKey: "position")
        e.setValue(job.completedAt, forKey: "completedAt")
        e.setValue(job.note, forKey: "note")
        e.setValue(Int64(job.photo?.bytes ?? 0), forKey: "photoBytes")
        e.setValue(job.photo?.sha256, forKey: "photoSHA256")
    }

    private func item(_ row: NSManagedObject) -> OutboxItem {
        let kind: OutboxItem.Kind = row.value(forKey: "kind") as? String == "complete"
            ? .complete(idempotencyKey: row.value(forKey: "idempotencyKey") as? String ?? "", body: row.value(forKey: "body") as? Data ?? Data())
            : .photo
        return OutboxItem(
            id: row.value(forKey: "id") as? UUID ?? UUID(), jobID: row.value(forKey: "jobID") as? String ?? "",
            kind: kind, sequence: row.value(forKey: "sequence") as? Int64 ?? 0,
            attempts: Int(row.value(forKey: "attempts") as? Int32 ?? 0),
            nextAttemptAt: row.value(forKey: "nextAttemptAt") as? Date,
            photoMismatches: Int(row.value(forKey: "photoMismatches") as? Int32 ?? 0))
    }
}
