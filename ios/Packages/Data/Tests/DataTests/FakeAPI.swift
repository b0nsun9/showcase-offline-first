import CryptoKit
import Domain
import Foundation
@testable import Data

/// A scripted server: records every call, answers from its scripts first, then like the real API.
actor FakeAPI: APIClienting {
    enum Call: Equatable { case list, complete(jobID: String, key: String, body: Data), upload(jobID: String, jpeg: Data) }

    private(set) var calls: [Call] = []
    private let ids: [String]
    private var completions: [String: SentBody] = [:]
    private var photos: [String: PhotoDTO] = [:]
    private var listFailures: [APIFailure] = []
    private var completeFailures: [APIFailure] = []
    private var uploadAnswers: [PhotoDTO] = []
    private var held: [CheckedContinuation<Void, Never>]?
    private var heldLists: [CheckedContinuation<Void, Never>]?

    init(jobIDs: [String]) { ids = jobIDs }

    /// The server's jobs, without recording a call.
    var jobs: [JobDTO] { ids.map(dto) }

    func failList(_ failures: APIFailure...) { listFailures += failures }
    func failComplete(_ failures: [APIFailure]) { completeFailures += failures }
    func answerUpload(_ answers: [PhotoDTO]) { uploadAnswers += answers }
    /// Holds every write that arrives until `release()`.
    func hold() { held = [] }
    func release() { held?.forEach { $0.resume() }; held = nil }
    /// Holds every list answer, as the server built it on arrival, until `releaseList()`.
    func holdList() { heldLists = [] }
    func releaseList() { heldLists?.forEach { $0.resume() }; heldLists = nil }

    func listJobs() async throws -> [JobDTO] {
        calls.append(.list)
        if !listFailures.isEmpty { throw listFailures.removeFirst() }
        let answer = jobs
        if heldLists != nil { await withCheckedContinuation { heldLists?.append($0) } }
        return answer
    }

    func complete(jobID: String, idempotencyKey: String, body: Data) async throws -> (job: JobDTO, replayed: Bool) {
        calls.append(.complete(jobID: jobID, key: idempotencyKey, body: body))
        await waitIfHeld()
        if !completeFailures.isEmpty { throw completeFailures.removeFirst() }
        completions[jobID] = try JSONDecoder().decode(SentBody.self, from: body)
        return (dto(jobID), false)
    }

    func uploadPhoto(jobID: String, jpeg: Data) async throws -> PhotoDTO {
        calls.append(.upload(jobID: jobID, jpeg: jpeg))
        await waitIfHeld()
        if !uploadAnswers.isEmpty { return uploadAnswers.removeFirst() }
        let photo = PhotoDTO(bytes: jpeg.count, sha256: SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined())
        photos[jobID] = photo
        return photo
    }

    private func waitIfHeld() async {
        guard held != nil else { return }
        await withCheckedContinuation { held?.append($0) }
    }

    private func dto(_ id: String) -> JobDTO {
        let done = completions[id]
        return JobDTO(id: id, address: "1 Main St", task: "Fix", date: "2026-11-06", windowStart: "09:00", windowEnd: "11:00",
                      status: done == nil ? "pending" : "completed", completedAt: done?.completedAt, note: done?.note,
                      photo: photos[id])
    }

    private struct SentBody: Decodable { let completedAt: String; let note: String? }
}

/// Stands in for `Task.sleep`: records each wait and suspends until the test wakes it or the sleeper is cancelled.
actor Sleeper {
    private(set) var requests: [TimeInterval] = []
    private var sleeping: [Int: CheckedContinuation<Void, Error>] = [:]

    var sleepingCount: Int { sleeping.count }

    func sleep(_ seconds: TimeInterval) async throws {
        let id = requests.count
        requests.append(seconds)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                park(id, continuation)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func park(_ id: Int, _ continuation: CheckedContinuation<Void, Error>) {
        if Task.isCancelled { continuation.resume(throwing: CancellationError()) } else { sleeping[id] = continuation }
    }

    /// Ends every wait in progress, as if its time had come.
    func wakeAll() {
        sleeping.values.forEach { $0.resume() }
        sleeping = [:]
    }

    private func cancel(_ id: Int) { sleeping.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

/// The time the code under test sees; only the test moves it.
final class TestTime: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) { current = date }

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

let testNow = Date(timeIntervalSince1970: 1_793_954_520)
let sentBody = CompletionBody.encode(completedAt: testNow, note: nil)
func fakeJPEG(_ jobID: String) -> Data { Data("jpeg of \(jobID)".utf8) }

/// An in-memory store whose jobs each have a photo (and, if `completed`, a queued completion keyed "key-<id>"),
/// a fake server, and an outbox on a test clock, a test sleep and no jitter.
struct Harness {
    let api: FakeAPI
    let store: JobStore
    let time: TestTime
    let sleeper: Sleeper
    let outbox: Outbox
    let defaults: UserDefaults

    init(jobs ids: [String], completed: Bool = true, jitter: Double = 1.0) async throws {
        let api = FakeAPI(jobIDs: ids), time = TestTime(testNow), sleeper = Sleeper()
        let store = try JobStore(storeURL: nil)
        try await store.apply(server: await api.jobs.map { $0.toDomain() })
        for id in ids {
            try await store.savePhoto(jobID: id, jpeg: fakeJPEG(id))
            if completed { try await store.complete(jobID: id, completedAt: testNow, idempotencyKey: "key-\(id)") }
        }
        let name = "DataTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        self.api = api
        self.store = store
        self.time = time
        self.sleeper = sleeper
        outbox = Outbox(store: store, api: api, now: { time.now }, sleep: { try await sleeper.sleep($0) }, jitter: { jitter })
    }

    func repository(network: AsyncStream<Bool> = AsyncStream { _ in }) -> LiveJobRepository {
        let time = time
        return LiveJobRepository(store: store, api: api, outbox: outbox, network: network, defaults: defaults, now: { time.now })
    }
}

extension JobStore {
    /// Applies a list answer as if it were requested just now.
    func apply(server: [Job]) async throws { try await apply(server: server, asOf: confirmations) }
}

/// Yields until `condition` holds. The suites have a time limit, so a condition that never holds fails the test
/// (the limit cancels the test, which ends the wait).
func eventually(_ condition: () async -> Bool) async {
    while !Task.isCancelled, !(await condition()) { await Task.yield() }
}
