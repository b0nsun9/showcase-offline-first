import Domain
@testable import FieldJobs
import Foundation
import Testing

@MainActor @Suite(.timeLimit(.minutes(1))) struct JobListViewModelTests {
    let someDate = Date(timeIntervalSince1970: 1_793_954_520)

    func makeViewModel(_ repository: FakeJobRepository) -> JobListViewModel {
        JobListViewModel(loadJobs: LoadJobs(repository: repository),
                         sendPendingWork: SendPendingWork(repository: repository),
                         formatTime: { _ in "08:12" })
    }

    /// A view model that has shown one snapshot.
    func shown(_ jobs: [Job] = [], updatedAt: Date? = nil, isOnline: Bool = true,
               sendingBlocked: Bool = false) async -> JobListViewModel {
        let snapshot = JobsSnapshot(jobs: jobs, updatedAt: updatedAt, isOnline: isOnline, sendingBlocked: sendingBlocked)
        let viewModel = makeViewModel(FakeJobRepository(snapshots: [snapshot]))
        await viewModel.start()
        return viewModel
    }

    func job(_ id: String, _ sync: SyncState = .notCompleted) -> Job {
        Job(id: id, address: "1 Main St", task: "Fix the tap", windowStart: "08:00", windowEnd: "09:00", sync: sync)
    }

    func jobs(_ count: Int, _ sync: SyncState) -> [Job] { (0..<count).map { job("\(sync)-\($0)", sync) } }

    @Test func rowsShowWindowAndStatus() async {
        let viewModel = await shown([job("a"), job("b", .waiting), job("c", .sent), job("d", .couldNotSend)], updatedAt: someDate)
        func row(_ id: String, _ status: String) -> JobRow {
            JobRow(id: id, window: "08:00–09:00", address: "1 Main St", task: "Fix the tap", status: status)
        }
        #expect(viewModel.rows == [
            row("a", "To do"), row("b", "Done · waiting"), row("c", "Done · sent"), row("d", "Done · couldn't send"),
        ])
    }

    @Test func showsEachNewSnapshot() async {
        let before = JobsSnapshot(jobs: [job("a")], updatedAt: someDate, isOnline: false, sendingBlocked: false)
        let after = JobsSnapshot(jobs: [job("a", .sent)], updatedAt: someDate, isOnline: true, sendingBlocked: false)
        let viewModel = makeViewModel(FakeJobRepository(snapshots: [before, after]))

        await viewModel.start()

        #expect(viewModel.rows.map(\.status) == ["Done · sent"])
        #expect(viewModel.banner == nil)
    }

    @Test func updatedTextUsesLastRefresh() async {
        #expect(await shown([job("a")], updatedAt: someDate).updatedText == "Updated 08:12")
        #expect(await shown([job("a")], updatedAt: nil).updatedText == nil)
    }

    @Test func bannerOfflineWithWaitingJobs() async {
        let one = await shown([job("a", .waiting), job("b", .sent), job("c", .couldNotSend), job("d")],
                              updatedAt: someDate, isOnline: false)
        #expect(one.banner == "No signal. 1 job is waiting to send and will go when the signal comes back.")

        let two = await shown(jobs(2, .waiting), updatedAt: someDate, isOnline: false)
        #expect(two.banner == "No signal. 2 jobs are waiting to send and will go when the signal comes back.")
    }

    @Test func bannerOfflineNothingWaiting() async {
        let viewModel = await shown([job("a"), job("b", .sent)], updatedAt: someDate, isOnline: false)
        #expect(viewModel.banner == "No signal. Showing the last list received.")
    }

    @Test func bannerOnlineWaiting() async {
        #expect(await shown(jobs(1, .waiting), updatedAt: someDate).banner == "1 job is waiting to send.")
        #expect(await shown(jobs(3, .waiting), updatedAt: someDate).banner == "3 jobs are waiting to send.")
    }

    @Test func bannerHiddenWhenOnlineAndIdle() async {
        #expect(await shown([job("a"), job("b", .sent), job("c", .couldNotSend)], updatedAt: someDate).banner == nil)
    }

    @Test func bannerSendingBlocked() async {
        let blocked = "Can't send right now because the app isn't set up correctly. Your work is safe on this phone."
        #expect(await shown(jobs(2, .waiting), updatedAt: someDate, isOnline: false, sendingBlocked: true).banner == blocked)
        #expect(await shown([job("a")], updatedAt: someDate, sendingBlocked: true).banner == blocked)
        #expect(await shown(sendingBlocked: true).banner == blocked)
    }

    @Test func emptyStateBeforeFirstList() async {
        let online = await shown()
        #expect(online.emptyMessage == "Today's jobs will load once there's signal.")
        #expect(online.rows.isEmpty)

        // There is no last list to show yet, so only the empty state speaks.
        let offline = await shown(isOnline: false)
        #expect(offline.emptyMessage == "Today's jobs will load once there's signal.")
        #expect(offline.banner == nil)

        #expect(await shown([job("a")], updatedAt: someDate).emptyMessage == nil)
    }

    @Test func refreshFailureStillSends() async {
        struct Offline: Error {}
        let fake = FakeJobRepository(refreshError: Offline())
        let viewModel = makeViewModel(fake)

        await viewModel.refresh()
        #expect(fake.calls == ["refresh", "sendPending"])

        await viewModel.appBecameActive()
        #expect(fake.calls == ["refresh", "sendPending", "refresh", "sendPending"])
    }
}
