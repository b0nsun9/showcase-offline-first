import Domain
import Foundation

/// Sends the queue oldest first, one pass at a time, and wakes itself when the earliest wait ends.
actor Outbox {
    enum Event: Sendable { case blockChanged, emptied }

    /// Block changes, and passes that sent something and left nothing to send. One consumer: the repository.
    nonisolated let events: AsyncStream<Event>
    private let emit: AsyncStream<Event>.Continuation
    private let store: JobStore
    private let api: any APIClienting
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let jitter: @Sendable () -> Double

    private(set) var sendingBlocked = false
    private var pausedUntil: Date? // a 429 covers the whole IP address, so it pauses every write
    private var running: Task<Void, Never>?
    private var runAgain = false
    private var wakeUp: Task<Void, Never>?

    init(store: JobStore, api: any APIClienting, now: @escaping @Sendable () -> Date,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void, jitter: @escaping @Sendable () -> Double) {
        self.store = store
        self.api = api
        self.now = now
        self.sleep = sleep
        self.jitter = jitter
        (events, emit) = AsyncStream.makeStream()
    }

    deinit { wakeUp?.cancel() }

    /// A refresh got 401 or `.missingKey`.
    func block() { setBlocked(true) }
    func unblock() { setBlocked(false) }

    /// One pass; concurrent callers wait for the running pass, then it runs once more.
    func drain() async {
        if let running {
            runAgain = true
            return await running.value
        }
        let passes = Task { await runPasses() }
        running = passes
        await passes.value
    }

    private func runPasses() async {
        repeat {
            runAgain = false
            // A store failure would fail again at once: wait for the next trigger instead of spinning.
            if await pass() { await scheduleWakeUp() }
        } while runAgain
        running = nil
    }

    /// Returns false if the store failed.
    private func pass() async -> Bool {
        do {
            var sent = false
            for item in try await store.dueItems(now: now()) {
                guard !sendingBlocked, !isPaused else { return true }
                if try await send(item) { sent = true }
            }
            if sent, try await store.dueItems(now: .distantFuture).isEmpty { emit.yield(.emptied) }
            return true
        } catch {
            return false
        }
    }

    /// Sends one item and records the answer. Returns whether the server confirmed it; store failures are thrown.
    private func send(_ item: OutboxItem) async throws -> Bool {
        do {
            switch item.kind {
            case let .complete(key, body):
                let answer = try await api.complete(jobID: item.jobID, idempotencyKey: key, body: body)
                try await store.finish(item, serverJob: answer.job.toDomain())
                return true
            case .photo:
                guard let jpeg = try await store.photoData(jobID: item.jobID) else {
                    try await store.markCouldNotSend(item)
                    return false
                }
                let answer = try await api.uploadPhoto(jobID: item.jobID, jpeg: jpeg)
                // The stored info is the phone's own size and hash of these bytes.
                let local = try await store.jobs().first { $0.id == item.jobID }?.photo
                if local == PhotoInfo(bytes: answer.bytes, sha256: answer.sha256) {
                    try await store.finish(item, serverJob: nil)
                    return true
                }
                if try await store.recordPhotoMismatch(item) >= 3 {
                    try await store.markCouldNotSend(item)
                } else {
                    try await store.reschedule(item, at: backoff(item), isBackoff: true)
                }
                return false
            }
        } catch let failure as APIFailure {
            switch sendDecision(for: failure) {
            case .retryWithBackoff: try await store.reschedule(item, at: backoff(item), isBackoff: true)
            case let .retryAfter(seconds): try await store.reschedule(item, at: now() + seconds, isBackoff: false)
            case let .pauseAllWrites(seconds): pausedUntil = now() + seconds
            case .stopAll: setBlocked(true)
            case .couldNotSend: try await store.markCouldNotSend(item)
            }
            return false
        }
    }

    /// `attempts` counts the failures before this one, so the first retry waits 2 seconds.
    private func backoff(_ item: OutboxItem) -> Date {
        now() + min(2 * pow(2, Double(item.attempts)), 300) * jitter()
    }

    private var isPaused: Bool { pausedUntil.map { now() < $0 } ?? false }

    private func setBlocked(_ blocked: Bool) {
        guard sendingBlocked != blocked else { return }
        sendingBlocked = blocked
        emit.yield(.blockChanged)
    }

    /// Keeps at most one wake-up alive, set for the earliest wait.
    private func scheduleWakeUp() async {
        wakeUp?.cancel()
        wakeUp = nil
        guard !sendingBlocked else { return } // only a successful refresh unblocks, and its callers drain next
        var date = try? await store.earliestWait()
        if isPaused { date = pausedUntil } // waits that end during the pause are due when it ends
        guard let date else { return }
        let sleep = sleep, delay = max(0, date.timeIntervalSince(now()))
        wakeUp = Task { [weak self] in
            guard (try? await sleep(delay)) != nil, !Task.isCancelled else { return }
            await self?.drain()
        }
    }
}
