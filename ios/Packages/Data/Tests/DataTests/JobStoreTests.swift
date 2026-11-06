import CryptoKit
import Domain
import Foundation
import Testing
@testable import Data

@Suite(.timeLimit(.minutes(1))) struct JobStoreTests {
    let now = Date(timeIntervalSince1970: 1_793_954_520)
    let jpeg = Data((0..<64).map { UInt8($0) })

    func job(_ id: String = "j1", completedAt: Date? = nil) -> Job {
        Job(id: id, address: "1 Main St", task: "Replace meter", windowStart: "09:00", windowEnd: "11:00", completedAt: completedAt)
    }

    /// An in-memory store holding one job that already has a photo.
    func readyStore() async throws -> JobStore {
        let store = try JobStore(storeURL: nil)
        try await store.apply(server: [job()])
        try await store.savePhoto(jobID: "j1", jpeg: jpeg)
        return store
    }

    @Test func completeQueuesCompletionThenPhotoInOneSave() async throws {
        let store = try await readyStore()
        let counter = Counter()
        let listener = Task { for await _ in store.changes { await counter.bump() } }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "key-1")
        try await store.apply(server: [job()]) // sentinel save: the count below must be 1 (complete) + 1 (sentinel)
        for _ in 0..<100 where await counter.value < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        listener.cancel()
        #expect(await counter.value == 2)

        let jobs = try await store.jobs()
        #expect(jobs[0].sync == .waiting)
        #expect(jobs[0].completedAt == now)
        let items = try await store.dueItems(now: now)
        #expect(items.map(\.kind) == [.complete(idempotencyKey: "key-1", body: CompletionBody.encode(completedAt: now, note: nil)), .photo])
        #expect(items[0].sequence < items[1].sequence)
    }

    @Test func completeFreezesDraftNote() async throws {
        let store = try await readyStore()
        try await store.saveNote(jobID: "j1", note: "x")
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let items = try await store.dueItems(now: now)
        #expect(items[0].kind == .complete(idempotencyKey: "k", body: CompletionBody.encode(completedAt: now, note: "x")))
        await #expect(throws: JobError.alreadyCompleted) { try await store.saveNote(jobID: "j1", note: "y") }
    }

    @Test func completingTwiceThrowsAlreadyCompleted() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        await #expect(throws: JobError.alreadyCompleted) { try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k2") }
        #expect(try await store.dueItems(now: now).count == 2)
    }

    @Test func completeWithoutPhotoThrowsPhotoMissing() async throws {
        let store = try JobStore(storeURL: nil)
        try await store.apply(server: [job()])
        await #expect(throws: JobError.photoMissing) { try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k") }
        #expect(try await store.dueItems(now: now).isEmpty)
        #expect(try await store.jobs()[0].completedAt == nil)
    }

    @Test func savePhotoStoresHashAndCount() async throws {
        let store = try await readyStore()
        let hex = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
        #expect(try await store.jobs()[0].photo == PhotoInfo(bytes: jpeg.count, sha256: hex))
        #expect(try await store.photoData(jobID: "j1") == jpeg)
    }

    @Test func secondPhotoThrowsPhotoAlreadyTaken() async throws {
        let store = try await readyStore()
        await #expect(throws: JobError.photoAlreadyTaken) { try await store.savePhoto(jobID: "j1", jpeg: Data([1])) }
    }

    @Test func queuedCompletionSurvivesReopeningStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("jobs.sqlite")
        let before: [OutboxItem]
        do {
            let store = try JobStore(storeURL: url)
            try await store.apply(server: [job()])
            try await store.saveNote(jobID: "j1", note: "kept")
            try await store.savePhoto(jobID: "j1", jpeg: jpeg)
            try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "key-disk")
            before = try await store.dueItems(now: now)
        }
        let reopened = try JobStore(storeURL: url)
        let after = try await reopened.dueItems(now: now)
        #expect(after.count == 2)
        #expect(after.map(\.kind) == before.map(\.kind))
        #expect(after[0].kind == .complete(idempotencyKey: "key-disk", body: CompletionBody.encode(completedAt: now, note: "kept")))
        #expect(try await reopened.photoData(jobID: "j1") == jpeg)
    }

    @Test func applyServerUsesMergeRule() async throws {
        let store = try JobStore(storeURL: nil)
        try await store.apply(server: [job()])
        try await store.saveNote(jobID: "j1", note: "draft")
        try await store.apply(server: [job()])
        #expect(try await store.jobs()[0].note == "draft")
    }

    @Test func syncStateFollowsOutbox() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let items = try await store.dueItems(now: now)
        try await store.markCouldNotSend(items[0])
        #expect(try await store.jobs()[0].sync == .couldNotSend)
        #expect(try await store.dueItems(now: now).map(\.kind) == [.photo])
        try await store.finish(items[0], serverJob: nil)
        try await store.finish(items[1], serverJob: nil)
        #expect(try await store.jobs()[0].sync == .sent)
    }

    @Test func confirmedJobKeepsPhotoBytes() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let info = try #require(try await store.jobs()[0].photo)
        var confirmed = job(completedAt: now)
        confirmed.photo = info
        for item in try await store.dueItems(now: now) { try await store.finish(item, serverJob: confirmed) }
        #expect(try await store.photoData(jobID: "j1") == jpeg)
        try await store.apply(server: [confirmed])
        #expect(try await store.photoData(jobID: "j1") == jpeg)
        #expect(try await store.jobs()[0].sync == .sent)
    }

    @Test func finishWithPhotolessServerJobKeepsLocalPhotoAndBlocksRetake() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let local = try #require(try await store.jobs()[0].photo)
        let items = try await store.dueItems(now: now)
        try await store.finish(items[0], serverJob: job(completedAt: now)) // server has photo: nil at this point
        #expect(try await store.jobs()[0].photo == local)
        #expect(try await store.photoData(jobID: "j1") == jpeg)
        await #expect(throws: JobError.photoAlreadyTaken) { try await store.savePhoto(jobID: "j1", jpeg: Data([1])) }
    }

    @Test func dueItemsRespectNextAttempt() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let first = try await store.dueItems(now: now)[0]
        try await store.reschedule(first, at: { _ in now.addingTimeInterval(10) }, isBackoff: true)
        #expect(try await store.dueItems(now: now).map(\.kind) == [.photo])
        let later = try await store.dueItems(now: now.addingTimeInterval(10))
        #expect(later.count == 2)
        #expect(later[0].attempts == 1)
        #expect(try await store.earliestWait() == now.addingTimeInterval(10))
    }

    @Test func clearBackoffWaitsKeepsRetryAfterWaits() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let items = try await store.dueItems(now: now)
        try await store.reschedule(items[0], at: { _ in now.addingTimeInterval(60) }, isBackoff: true)
        try await store.reschedule(items[1], at: { _ in now.addingTimeInterval(60) }, isBackoff: false)
        try await store.clearBackoffWaits()
        #expect(try await store.dueItems(now: now).map(\.kind) == [items[0].kind])
        // Back to the first wait for the backoff item; the Retry-After item keeps its count.
        #expect(try await store.dueItems(now: .distantFuture).map(\.attempts) == [0, 1])
    }

    @Test func recordPhotoMismatchCounts() async throws {
        let store = try await readyStore()
        try await store.complete(jobID: "j1", completedAt: now, idempotencyKey: "k")
        let photo = try await store.dueItems(now: now)[1]
        #expect(try await store.recordPhotoMismatch(photo) == 1)
        #expect(try await store.recordPhotoMismatch(photo) == 2)
    }
}

actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
