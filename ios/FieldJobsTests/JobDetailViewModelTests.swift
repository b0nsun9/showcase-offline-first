import Domain
@testable import FieldJobs
import Foundation
import Testing

@MainActor @Suite(.timeLimit(.minutes(1))) struct JobDetailViewModelTests {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    let info = PhotoInfo(bytes: 4, sha256: "abc")
    let someDate = Date(timeIntervalSince1970: 1_793_954_520)

    func job(photo: PhotoInfo? = nil, note: String? = nil, completedAt: Date? = nil,
             sync: SyncState = .notCompleted) -> Job {
        Job(id: "job-1", address: "1 Main St", task: "Fix the tap", windowStart: "08:00", windowEnd: "09:00",
            photo: photo, note: note, completedAt: completedAt, sync: sync)
    }

    /// Stores `job`, and the photo bytes when it has photo info.
    func fake(_ job: Job, holdsComplete: Bool = false) -> FakeJobRepository {
        FakeJobRepository(snapshots: [JobsSnapshot(jobs: [job], updatedAt: someDate, isOnline: true, sendingBlocked: false)],
                          photo: job.photo == nil ? nil : jpeg, holdsComplete: holdsComplete)
    }

    /// A view model that has shown `fake`'s job.
    func shown(_ fake: FakeJobRepository) async -> JobDetailViewModel {
        let viewModel = JobDetailViewModel(
            jobID: "job-1", loadJobs: LoadJobs(repository: fake), attachPhoto: AttachPhoto(repository: fake),
            saveNote: SaveNote(repository: fake), completeJob: CompleteJob(repository: fake),
            sendPendingWork: SendPendingWork(repository: fake), formatTime: { _ in "11:34" })
        await viewModel.start()
        return viewModel
    }

    func shown(_ job: Job) async -> JobDetailViewModel { await shown(fake(job)) }

    /// Waits up to 2 seconds for work the view model started in a `Task` of its own.
    func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @Test func completeDisabledWithoutPhoto() async {
        let viewModel = await shown(job())
        #expect(viewModel.job != nil)
        #expect(viewModel.photo == nil)
        #expect(viewModel.canComplete == false)
    }

    @Test func completeEnabledWithPhotoAndShortNote() async {
        let viewModel = await shown(job(photo: info))
        #expect(viewModel.canComplete)
        viewModel.note = "Fixed the washer."
        #expect(viewModel.canComplete)
    }

    @Test func counterCountsUTF16() async {
        let viewModel = await shown(job())
        #expect(viewModel.noteCounter == "0 / 1000")
        viewModel.note = String(repeating: "👍", count: 22)
        #expect(viewModel.noteCounter == "44 / 1000")
    }

    @Test func completeDisabledWhenNoteTooLong() async {
        let viewModel = await shown(job(photo: info))
        viewModel.note = String(repeating: "👍", count: 501)
        #expect(viewModel.canComplete == false)
        viewModel.note = String(repeating: "👍", count: 500)
        #expect(viewModel.canComplete)
    }

    @Test func completeIsDisabledWhileCompleting() async throws {
        let fake = fake(job(photo: info), holdsComplete: true)
        let viewModel = await shown(fake)

        let first = Task { await viewModel.complete() }
        await eventually { fake.calls.contains("complete(job-1)") }
        try #require(fake.calls.contains("complete(job-1)")) // otherwise the release below comes first, and `first` never ends
        #expect(viewModel.canComplete == false)
        await viewModel.complete()

        fake.releaseComplete()
        await first.value
        #expect(viewModel.canComplete == false)
        #expect(fake.calls.filter { $0 == "complete(job-1)" }.count == 1)
    }

    @Test func photoCanBeTakenOnlyOnce() async {
        let fake = fake(job())
        let viewModel = await shown(fake)
        #expect(viewModel.canTakePhoto)

        await viewModel.photoTaken(jpeg)

        #expect(viewModel.photo == jpeg)
        #expect(viewModel.canTakePhoto == false)
        #expect(viewModel.canComplete)
        await viewModel.photoTaken(jpeg)
        #expect(fake.calls == ["savePhoto(job-1)"])
    }

    @Test func noteChangesSaveDraft() async {
        let fake = fake(job())
        let viewModel = await shown(fake)

        viewModel.note = "x"

        await eventually { !fake.calls.isEmpty }
        #expect(fake.calls == ["saveNote(job-1, x)"])
    }

    @Test func statusLineAfterComplete() async {
        #expect(await shown(job(photo: info)).statusLine == nil)
        #expect(await shown(job(photo: info, completedAt: someDate, sync: .waiting)).statusLine
                == "Completed 11:34 · waiting to send")
        #expect(await shown(job(photo: info, completedAt: someDate, sync: .sent)).statusLine == "Completed 11:34 · sent")
        #expect(await shown(job(photo: info, completedAt: someDate, sync: .couldNotSend)).statusLine
                == "Completed 11:34 · couldn't send")
    }

    @Test func completedJobIsLocked() async {
        let completed = await shown(job(photo: info, completedAt: someDate, sync: .waiting))
        #expect(completed.canTakePhoto == false)
        #expect(completed.canComplete == false)

        // Completed elsewhere: the phone has no photo, and still can't add one.
        let fromServer = await shown(job(completedAt: someDate, sync: .sent))
        #expect(fromServer.canTakePhoto == false)
        #expect(fromServer.canComplete == false)
    }

    @Test func startShowsTheSavedDraftWithoutSavingIt() async {
        let fake = fake(job(photo: info, note: "Left at the door"))
        let viewModel = await shown(fake)

        #expect(viewModel.job?.address == "1 Main St")
        #expect(viewModel.note == "Left at the door")
        #expect(viewModel.photo == jpeg)
        try? await Task.sleep(nanoseconds: 100_000_000) // longer than the fake's save
        #expect(fake.calls.isEmpty)
    }

    @Test func completeSavesTheLastNoteFirst() async {
        let fake = fake(job(photo: info))
        let viewModel = await shown(fake)

        viewModel.note = "Done"
        await viewModel.complete()

        #expect(Array(fake.calls.prefix(2)) == ["saveNote(job-1, Done)", "complete(job-1)"])
    }

    @Test func completeThenSends() async {
        let fake = fake(job(photo: info))
        let viewModel = await shown(fake)

        await viewModel.complete()

        await eventually { fake.calls.count == 2 }
        #expect(fake.calls == ["complete(job-1)", "sendPending"])
    }
}
