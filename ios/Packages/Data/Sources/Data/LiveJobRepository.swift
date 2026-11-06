import Domain
import Foundation

/// The app's `JobRepository`: the store is what the screens show, the outbox sends what is queued.
public final class LiveJobRepository: JobRepository, @unchecked Sendable {
    private let store: JobStore
    private let api: any APIClienting
    private let outbox: Outbox
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var isOnline: Bool? // nil until the first report, so a launch with signal resets waits like a reconnect
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var tasks: [Task<Void, Never>] = []

    public static func make(host: String, apiKey: String, defaults: UserDefaults = .standard, storeURL: URL) throws -> LiveJobRepository {
        let config = APIConfig(host: host, apiKey: apiKey, installID: InstallID.current(in: defaults))
        let api = APIClient(config: config, session: URLSession(configuration: .ephemeral))
        let store = try JobStore(storeURL: storeURL)
        let outbox = Outbox(store: store, api: api, now: Date.init,
                            sleep: { try await Task.sleep(nanoseconds: nanoseconds($0)) },
                            jitter: { Double.random(in: 0.8...1.2) })
        return LiveJobRepository(store: store, api: api, outbox: outbox, network: NetworkMonitor.paths(),
                                 defaults: defaults, now: Date.init)
    }

    /// Saturates at about 31 years: `UInt64(seconds * 1e9)` traps above about 1.8e10 seconds.
    static func nanoseconds(_ seconds: TimeInterval) -> UInt64 { seconds > 0 ? UInt64(min(seconds, 1e9) * 1e9) : 0 }

    init(store: JobStore, api: any APIClienting, outbox: Outbox, network: AsyncStream<Bool>, defaults: UserDefaults,
         now: @escaping @Sendable () -> Date) {
        self.store = store
        self.api = api
        self.outbox = outbox
        self.defaults = defaults
        self.now = now
        let changes = store.changes, events = outbox.events
        tasks = [
            Task { [weak self] in for await _ in changes { self?.notify() } },
            Task { [weak self] in for await online in network { await self?.networkChanged(online) } },
            Task { [weak self] in for await event in events { await self?.handle(event) } },
        ]
    }

    deinit {
        tasks.forEach { $0.cancel() }
        listeners.values.forEach { $0.finish() }
    }

    public func snapshots() -> AsyncStream<JobsSnapshot> {
        let key = UUID()
        // Holds at most one pending tick: a burst of changes yields one snapshot of the latest state.
        let ticks = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { tick in
            lock.withLock { listeners[key] = tick }
            tick.yield() // the current state at once
        }
        return AsyncStream { output in
            let task = Task { [weak self] in
                for await _ in ticks {
                    if let snapshot = try? await self?.snapshot() { output.yield(snapshot) }
                }
                output.finish()
            }
            output.onTermination = { [weak self] _ in
                task.cancel()
                self?.lock.withLock { self?.listeners[key] = nil }
            }
        }
    }

    public func refresh() async throws {
        do {
            let jobs = try await api.listJobs()
            try await store.apply(server: jobs.map { $0.toDomain() })
            await outbox.unblock() // the server accepted the key: the only evidence that clears a 401 block
        } catch let failure as APIFailure {
            if sendDecision(for: failure) == .stopAll { await outbox.block() }
            throw failure
        }
        defaults.set(now(), forKey: "lastRefreshAt")
        notify()
    }

    public func job(id: String) async throws -> Job? { try await store.jobs().first { $0.id == id } }
    public func photoData(jobID: String) async throws -> Data? { try await store.photoData(jobID: jobID) }
    public func savePhoto(jobID: String, jpeg: Data) async throws { try await store.savePhoto(jobID: jobID, jpeg: jpeg) }
    public func saveNote(jobID: String, note: String?) async throws { try await store.saveNote(jobID: jobID, note: note) }

    public func complete(jobID: String, completedAt: Date) async throws {
        try await store.complete(jobID: jobID, completedAt: completedAt, idempotencyKey: UUID().uuidString)
    }

    public func sendPending() async { await outbox.drain() }

    private func snapshot() async throws -> JobsSnapshot {
        let jobs = try await store.jobs()
        let blocked = await outbox.sendingBlocked
        return JobsSnapshot(jobs: jobs, updatedAt: defaults.object(forKey: "lastRefreshAt") as? Date,
                            isOnline: lock.withLock { isOnline ?? true }, sendingBlocked: blocked)
    }

    private func notify() {
        lock.withLock { Array(listeners.values) }.forEach { $0.yield() }
    }

    private func networkChanged(_ online: Bool) async {
        let wasOnline = lock.withLock { () -> Bool? in
            let was = isOnline
            isOnline = online
            return was
        }
        guard online != wasOnline else { return }
        notify()
        guard online else { return }
        try? await store.clearBackoffWaits()
        try? await refresh()
        await outbox.drain()
    }

    private func handle(_ event: Outbox.Event) async {
        switch event {
        case .blockChanged: notify()
        case .emptied: try? await refresh()
        }
    }
}
