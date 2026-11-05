import Domain
import Foundation
import Testing

@Suite struct UseCaseTests {
    let fixedNow = Date(timeIntervalSince1970: 1_793_954_520)

    @Test func completeWithoutPhotoThrowsPhotoMissing() async {
        let fake = FakeJobRepository(jobs: [.make()])
        await #expect(throws: JobError.photoMissing) { try await CompleteJob(repository: fake)(jobID: "job-1") }
        #expect(fake.completeCalls.isEmpty)
    }

    @Test func noteLimitCountsUTF16() async throws {
        let thumbs500 = String(repeating: "👍", count: 500)
        let thumbs501 = String(repeating: "👍", count: 501)

        let ok = FakeJobRepository(jobs: [.make(photo: somePhoto, note: thumbs500)])
        try await CompleteJob(repository: ok)(jobID: "job-1")
        #expect(ok.completeCalls.count == 1)

        let tooLong = FakeJobRepository(jobs: [.make(photo: somePhoto, note: thumbs501)])
        await #expect(throws: JobError.noteTooLong) { try await CompleteJob(repository: tooLong)(jobID: "job-1") }
        #expect(tooLong.completeCalls.isEmpty)

        let save = SaveNote(repository: ok)
        try await save(jobID: "job-1", note: thumbs500)
        await #expect(throws: JobError.noteTooLong) { try await save(jobID: "job-1", note: thumbs501) }
    }

    @Test func completeTwiceThrowsAlreadyCompleted() async {
        let fake = FakeJobRepository(jobs: [.make(photo: somePhoto, completedAt: fixedNow, sync: .waiting)])
        await #expect(throws: JobError.alreadyCompleted) { try await CompleteJob(repository: fake)(jobID: "job-1") }
        #expect(fake.completeCalls.isEmpty)
    }

    @Test func completePassesNowAsCompletedAt() async throws {
        let fake = FakeJobRepository(jobs: [.make(photo: somePhoto)])
        let now = fixedNow
        try await CompleteJob(repository: fake, now: { now })(jobID: "job-1")
        #expect(fake.completeCalls.count == 1)
        #expect(fake.completeCalls[0].0 == "job-1")
        #expect(fake.completeCalls[0].1 == fixedNow)
    }

    @Test func attachPhotoOverLimitThrowsPhotoTooLarge() async {
        let fake = FakeJobRepository(jobs: [.make()])
        await #expect(throws: JobError.photoTooLarge) {
            try await AttachPhoto(repository: fake)(jobID: "job-1", jpeg: Data(count: 5_242_881))
        }
        #expect(fake.photoCalls.isEmpty)
    }

    @Test func attachSecondPhotoThrowsPhotoAlreadyTaken() async {
        let fake = FakeJobRepository(jobs: [.make(photo: somePhoto)])
        await #expect(throws: JobError.photoAlreadyTaken) {
            try await AttachPhoto(repository: fake)(jobID: "job-1", jpeg: Data(count: 10))
        }
        #expect(fake.photoCalls.isEmpty)
    }

    @Test func saveNoteStoresEmptyAsNil() async throws {
        let fake = FakeJobRepository(jobs: [.make()])
        try await SaveNote(repository: fake)(jobID: "job-1", note: "")
        #expect(fake.noteCalls.count == 1)
        #expect(fake.noteCalls[0].0 == "job-1")
        #expect(fake.noteCalls[0].1 == nil)
    }

    @Test func unknownJobThrowsUnknownJob() async {
        let fake = FakeJobRepository()
        await #expect(throws: JobError.unknownJob) { try await CompleteJob(repository: fake)(jobID: "nope") }
        await #expect(throws: JobError.unknownJob) {
            try await AttachPhoto(repository: fake)(jobID: "nope", jpeg: Data(count: 1))
        }
    }
}
