import Domain
import Foundation
import Testing

@Suite struct JobMergeTests {
    let done = Date(timeIntervalSince1970: 1_793_954_520)

    @Test func mergePhoneWinsWhileCompletionUnsent() {
        let local = Job.make(photo: somePhoto, completedAt: done, sync: .waiting)
        let server = Job.make(task: "Server task")
        #expect(JobMerge.merge(local: [local], server: [server]) == [local])
    }

    @Test func mergeServerWinsWhenNothingPending() {
        let local = Job.make(completedAt: done, sync: .sent)
        let server = Job.make(task: "Changed", completedAt: done, sync: .sent)
        #expect(JobMerge.merge(local: [local], server: [server]) == [server])
    }

    @Test func mergeKeepsDraftOfPendingJob() {
        let local = Job.make(task: "Old", photo: somePhoto, note: "draft")
        let server = Job.make(address: "2 New St", task: "New")
        let merged = JobMerge.merge(local: [local], server: [server])
        #expect(merged == [Job.make(address: "2 New St", task: "New", photo: somePhoto, note: "draft")])
    }

    @Test func mergeKeepsCouldNotSendJob() {
        let local = Job.make(photo: somePhoto, completedAt: done, sync: .couldNotSend)
        let server = Job.make(task: "Server task")
        #expect(JobMerge.merge(local: [local], server: [server]) == [local])
    }

    @Test func mergeKeepsPendingJobMissingFromServer() {
        let pending = Job.make(id: "job-9", photo: somePhoto, completedAt: done, sync: .waiting)
        let server = Job.make(id: "job-1")
        #expect(JobMerge.merge(local: [pending], server: [server]) == [server, pending])
    }

    @Test func mergeDropsSentJobMissingFromServer() {
        let sent = Job.make(id: "job-9", completedAt: done, sync: .sent)
        #expect(JobMerge.merge(local: [sent], server: []).isEmpty)
    }

    @Test func mergeFollowsServerOrder() {
        let a = Job.make(id: "a"), b = Job.make(id: "b"), c = Job.make(id: "c")
        let merged = JobMerge.merge(local: [a, b, c], server: [c, a, b])
        #expect(merged.map(\.id) == ["c", "a", "b"])
    }
}
