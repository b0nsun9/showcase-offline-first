import Domain
import Foundation
import Testing
@testable import Data

@Suite(.timeLimit(.minutes(1))) struct OutboxTests {
    let complete1 = FakeAPI.Call.complete(jobID: "job-1", key: "key-job-1", body: sentBody)
    let upload1 = FakeAPI.Call.upload(jobID: "job-1", jpeg: fakeJPEG("job-1"))

    @Test func successfulCompletionAndPhotoMarkJobSent() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.outbox.drain()
        #expect(try await h.store.jobs()[0].sync == .sent)
        #expect(await h.api.calls == [complete1, upload1])
        #expect(try await h.store.dueItems(now: .distantFuture).isEmpty)
    }

    @Test func retryAfterDroppedAnswerReusesKeyAndBody() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete([.transport])
        await h.outbox.drain()
        #expect(try await h.store.dueItems(now: .distantFuture).first?.nextAttemptAt == testNow + 2)
        h.time.advance(2)
        await h.outbox.drain()
        let completions = await h.api.calls.filter { $0 != upload1 }
        #expect(completions == [complete1, complete1])
        #expect(try await h.store.jobs()[0].sync == .sent)
    }

    @Test func backoffDoublesAndCaps() async throws {
        let waits: [TimeInterval] = [2, 4, 8, 16, 32, 64, 128, 256, 300, 300]
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete(Array(repeating: .transport, count: waits.count))
        await h.outbox.drain()
        for (index, wait) in waits.enumerated() {
            await eventually { await h.sleeper.requests.count == index + 1 }
            if index < waits.count - 1 {
                h.time.advance(wait)
                await h.sleeper.wakeAll() // the wake-up Task drains again
            }
        }
        #expect(await h.sleeper.requests == waits)
    }

    @Test func backoffAppliesJitter() async throws {
        let h = try await Harness(jobs: ["job-1"], jitter: 1.2)
        await h.api.failComplete([.transport])
        await h.outbox.drain()
        #expect(try await h.store.dueItems(now: .distantFuture).first?.nextAttemptAt == testNow + 2.4)
    }

    @Test func conflictWaitsRetryAfter() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete([.http(status: 409, code: "request_in_progress", retryAfter: 7)])
        await h.outbox.drain()
        #expect(try await h.store.dueItems(now: .distantFuture).first?.nextAttemptAt == testNow + 7)
        await eventually { await h.sleeper.requests == [7] }
        await h.outbox.drain() // nothing is due yet; the new wake-up replaces the old one
        await eventually {
            let requests = await h.sleeper.requests, sleeping = await h.sleeper.sleepingCount
            return requests == [7, 7] && sleeping == 1
        }
    }

    @Test func writeLimitPausesEveryWrite() async throws {
        let h = try await Harness(jobs: ["job-1", "job-2"])
        await h.api.failComplete([.http(status: 429, code: "write_limit_reached", retryAfter: 120)])
        await h.outbox.drain()
        #expect(await h.api.calls == [complete1])
        await eventually { await h.sleeper.requests == [120] }
        h.time.advance(60)
        await h.outbox.drain()
        #expect(await h.api.calls == [complete1])
        h.time.advance(60)
        await h.outbox.drain()
        #expect(await h.api.calls.count == 5)
        #expect(try await h.store.jobs().map(\.sync) == [.sent, .sent])
    }

    @Test func missingKeyBlocksSending() async throws {
        let h = try await Harness(jobs: ["job-1"])
        await h.api.failComplete([.missingKey])
        await h.outbox.drain()
        #expect(await h.outbox.sendingBlocked)
        await h.outbox.drain()
        #expect(await h.api.calls == [complete1])
        #expect(try await h.store.dueItems(now: testNow).count == 2)
    }

    @Test func permanentErrorMarksCouldNotSendAndContinues() async throws {
        let h = try await Harness(jobs: ["job-1", "job-2"])
        await h.api.failComplete([.http(status: 422, code: "idempotency_key_reused", retryAfter: nil)])
        await h.outbox.drain()
        #expect(try await h.store.jobs().map(\.sync) == [.couldNotSend, .sent])
        #expect(await h.api.calls.count == 4)
    }

    @Test func photoHashMismatchRetriesThenGivesUpAtThree() async throws {
        func run(mismatches: Int) async throws -> (SyncState, uploads: Int) {
            let h = try await Harness(jobs: ["job-1"])
            await h.api.answerUpload(Array(repeating: PhotoDTO(bytes: 1, sha256: "bad"), count: mismatches))
            for _ in 0..<3 {
                await h.outbox.drain()
                if let wait = try await h.store.earliestWait() { h.time.set(wait) }
            }
            let uploads = await h.api.calls.filter { $0 == upload1 }.count
            return (try await h.store.jobs()[0].sync, uploads)
        }
        let givenUp = try await run(mismatches: 3)
        #expect(givenUp.0 == .couldNotSend)
        #expect(givenUp.uploads == 3)
        let matched = try await run(mismatches: 2)
        #expect(matched.0 == .sent)
        #expect(matched.uploads == 3)
    }

    @Test func emptiedIsReportedOnlyAfterSending() async throws {
        let idle = try await Harness(jobs: ["job-1"], completed: false)
        await idle.outbox.drain()
        await idle.outbox.block()
        var events = idle.outbox.events.makeAsyncIterator()
        #expect(await events.next() == .blockChanged)

        let busy = try await Harness(jobs: ["job-1"])
        await busy.outbox.drain()
        var busyEvents = busy.outbox.events.makeAsyncIterator()
        #expect(await busyEvents.next() == .emptied)
    }
}
