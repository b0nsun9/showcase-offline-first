import Domain
import Foundation
import Testing
@testable import Data

@Suite(.timeLimit(.minutes(1))) struct LiveJobRepositoryTests {
    let complete1 = FakeAPI.Call.complete(jobID: "job-1", key: "key-job-1", body: sentBody)
    let upload1 = FakeAPI.Call.upload(jobID: "job-1", jpeg: fakeJPEG("job-1"))

    @Test func unauthorizedBlocksUntilSendPending() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete([.http(status: 401, code: "unauthorized", retryAfter: nil)])
        let repo = h.repository()
        await repo.sendPending()
        let blocked = await repo.snapshot { $0.sendingBlocked }
        #expect(blocked?.jobs.first?.sync == .waiting)
        #expect(try await h.store.dueItems(now: testNow).count == 2)
        #expect(await h.api.calls == [complete1])
        await repo.sendPending()
        let sent = await repo.snapshot()
        #expect(sent?.sendingBlocked == false)
        #expect(sent?.jobs.first?.sync == .sent)
    }

    @Test func concurrentSendPendingSendsEachItemOnce() async throws {
        let h = try await Harness(jobs: ["job-1", "job-2"], completed: false)
        try await h.store.complete(jobID: "job-1", completedAt: testNow, idempotencyKey: "key-job-1")
        let repo = h.repository()
        await h.api.hold()
        async let first: Void = repo.sendPending()
        await eventually { await h.api.calls.count == 1 }
        // Completed while the first pass is in flight: the waiting caller's extra pass must send it.
        try await h.store.complete(jobID: "job-2", completedAt: testNow, idempotencyKey: "key-job-2")
        async let second: Void = repo.sendPending()
        for _ in 0..<200 { await Task.yield() } // give a second sender every chance to resend the held item
        await h.api.release()
        _ = await (first, second)
        let complete2 = FakeAPI.Call.complete(jobID: "job-2", key: "key-job-2", body: sentBody)
        let upload2 = FakeAPI.Call.upload(jobID: "job-2", jpeg: fakeJPEG("job-2"))
        #expect(await h.api.calls.filter { $0 != .list } == [complete1, upload1, complete2, upload2])
    }

    @Test func networkReturnClearsBackoffAndSends() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete([.transport])
        let (network, link) = AsyncStream.makeStream(of: Bool.self)
        let repo = h.repository(network: network)
        await repo.sendPending() // the completion now waits 2 s of backoff; the clock never moves
        #expect(try await h.store.dueItems(now: testNow).isEmpty)
        link.yield(false)
        #expect(await repo.snapshot { !$0.isOnline } != nil)
        link.yield(true)
        #expect(await repo.snapshot { $0.isOnline && $0.jobs.first?.sync == .sent } != nil)
        #expect(Array(await h.api.calls.prefix(4)) == [complete1, upload1, .list, complete1])
    }

    @Test func networkReturnResetsBackoffToFirstWait() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete(Array(repeating: .transport, count: 4))
        let (network, link) = AsyncStream.makeStream(of: Bool.self)
        let repo = h.repository(network: network)
        for wait: TimeInterval in [2, 4, 8] {
            await repo.sendPending()
            h.time.advance(wait)
        }
        link.yield(false)
        link.yield(true) // the path says online before the route works: one more transport failure
        await eventually { await h.sleeper.requests.count == 4 }
        #expect(await h.sleeper.requests == [2, 4, 8, 2])
    }

    @Test func productionSleepSaturates() {
        #expect(LiveJobRepository.nanoseconds(2) == 2_000_000_000)
        #expect(LiveJobRepository.nanoseconds(1e11) == 1_000_000_000_000_000_000)
        #expect(LiveJobRepository.nanoseconds(.infinity) == 1_000_000_000_000_000_000)
        #expect(LiveJobRepository.nanoseconds(-1) == 0)
    }

    @Test func refreshFailureKeepsListAndUpdatedAt() async throws {
        let h = try await Harness(jobs: ["job-1"], completed: false)
        let repo = h.repository()
        try await repo.refresh()
        let before = await repo.snapshot()
        #expect(before?.updatedAt == testNow)
        h.time.advance(60)
        await h.api.failList(.transport)
        await #expect(throws: APIFailure.transport) { try await repo.refresh() }
        let after = await repo.snapshot()
        #expect(after?.jobs.count == 1)
        #expect(after?.jobs == before?.jobs)
        #expect(after?.updatedAt == testNow)
        #expect(after?.sendingBlocked == false)
    }

    @Test func refreshUnauthorizedBlocksSending() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failList(.http(status: 401, code: "unauthorized", retryAfter: nil))
        let repo = h.repository()
        await #expect(throws: APIFailure.self) { try await repo.refresh() }
        #expect(await repo.snapshot()?.sendingBlocked == true)
        await h.outbox.drain()
        #expect(await h.api.calls == [.list])
    }

    @Test func completeUsesFreshKeyPerJob() async throws {
        let h = try await Harness(jobs: ["job-1", "job-2"], completed: false)
        let repo = h.repository()
        try await repo.complete(jobID: "job-1", completedAt: testNow)
        try await repo.complete(jobID: "job-2", completedAt: testNow)
        let keys = try await h.store.dueItems(now: testNow).compactMap { item -> String? in
            if case let .complete(key, _) = item.kind { return key }
            return nil
        }
        #expect(keys.count == 2)
        #expect(Set(keys).count == 2)
        #expect(keys.allSatisfy { UUID(uuidString: $0) != nil })
    }

    @Test func refreshAfterQueueEmpties() async throws {
        let h = try await Harness(jobs: ["job-1"])
        let repo = h.repository()
        await repo.sendPending()
        await eventually { await h.api.calls.count == 3 }
        #expect(await h.api.calls == [complete1, upload1, .list])
        let refreshed = await repo.snapshot { $0.updatedAt != nil }
        #expect(refreshed?.updatedAt == testNow)
        #expect(refreshed?.jobs.first?.sync == .sent)
    }
}

extension LiveJobRepository {
    /// The first snapshot that satisfies `condition`.
    func snapshot(where condition: (JobsSnapshot) -> Bool = { _ in true }) async -> JobsSnapshot? {
        for await snapshot in snapshots() where condition(snapshot) { return snapshot }
        return nil
    }
}
