import Combine
import Domain
import Foundation

struct JobRow: Equatable, Identifiable {
    let id: String
    let window: String
    let address: String
    let task: String
    let status: String
}

@MainActor final class JobListViewModel: ObservableObject {
    @Published private(set) var rows: [JobRow] = []
    @Published private(set) var updatedText: String?
    @Published private(set) var banner: String?
    @Published private(set) var emptyMessage: String?

    private let loadJobs: LoadJobs
    private let sendPendingWork: SendPendingWork
    private let formatTime: (Date) -> String

    init(loadJobs: LoadJobs, sendPendingWork: SendPendingWork, formatTime: @escaping (Date) -> String) {
        self.loadJobs = loadJobs
        self.sendPendingWork = sendPendingWork
        self.formatTime = formatTime
    }

    /// Shows every snapshot until the stream ends or the task is cancelled.
    func start() async {
        for await snapshot in loadJobs.snapshots() { show(snapshot) }
    }

    /// A failed refresh keeps the last list; queued work is sent either way.
    func refresh() async {
        try? await loadJobs.refresh()
        await sendPendingWork()
    }

    func appBecameActive() async { await refresh() }

    private func show(_ snapshot: JobsSnapshot) {
        let hasList = !snapshot.jobs.isEmpty || snapshot.updatedAt != nil
        rows = snapshot.jobs.map { JobRow($0) }
        updatedText = snapshot.updatedAt.map { "Updated \(formatTime($0))" }
        emptyMessage = hasList ? nil : "Today's jobs will load once there's signal."
        banner = Self.banner(for: snapshot, hasList: hasList)
    }

    private static func banner(for snapshot: JobsSnapshot, hasList: Bool) -> String? {
        if snapshot.sendingBlocked {
            return "Can't send right now because the app isn't set up correctly. Your work is safe on this phone."
        }
        let waiting = snapshot.jobs.filter { $0.sync == .waiting }.count
        let jobs = waiting == 1 ? "1 job is" : "\(waiting) jobs are"
        switch (snapshot.isOnline, waiting) {
        case (false, 0): return hasList ? "No signal. Showing the last list received." : nil
        case (false, _): return "No signal. \(jobs) waiting to send and will go when the signal comes back."
        case (true, 0): return nil
        case (true, _): return "\(jobs) waiting to send."
        }
    }
}

private extension JobRow {
    init(_ job: Job) {
        self.init(id: job.id, window: "\(job.windowStart)–\(job.windowEnd)", address: job.address, task: job.task,
                  status: Self.status(job.sync))
    }

    static func status(_ sync: SyncState) -> String {
        switch sync {
        case .notCompleted: "To do"
        case .waiting: "Done · waiting"
        case .sent: "Done · sent"
        case .couldNotSend: "Done · couldn't send"
        }
    }
}
