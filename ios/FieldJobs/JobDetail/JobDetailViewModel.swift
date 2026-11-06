import Combine
import Domain
import Foundation

@MainActor final class JobDetailViewModel: ObservableObject {
    @Published private(set) var job: Job?
    @Published private(set) var photo: Data?
    @Published var note = "" {
        didSet { if !isShowingSavedNote { saveDraft() } }
    }
    @Published private var isCompleting = false

    private let jobID: String
    private let loadJobs: LoadJobs
    private let attachPhoto: AttachPhoto
    private let saveNote: SaveNote
    private let completeJob: CompleteJob
    private let sendPendingWork: SendPendingWork
    private let formatTime: (Date) -> String
    private var isShowingSavedNote = false
    private var noteSave: Task<Void, Never>?

    init(jobID: String, loadJobs: LoadJobs, attachPhoto: AttachPhoto, saveNote: SaveNote,
         completeJob: CompleteJob, sendPendingWork: SendPendingWork, formatTime: @escaping (Date) -> String) {
        self.jobID = jobID
        self.loadJobs = loadJobs
        self.attachPhoto = attachPhoto
        self.saveNote = saveNote
        self.completeJob = completeJob
        self.sendPendingWork = sendPendingWork
        self.formatTime = formatTime
    }

    var noteCounter: String { "\(note.utf16.count) / \(Job.noteLimit)" }

    var canComplete: Bool {
        guard let job, job.completedAt == nil else { return false }
        return photo != nil && note.utf16.count <= Job.noteLimit && !isCompleting
    }

    var canEditNote: Bool { job?.completedAt == nil && !isCompleting }

    var canTakePhoto: Bool {
        guard let job else { return false }
        return photo == nil && job.photo == nil && job.completedAt == nil
    }

    var statusLine: String? {
        guard let job, let completedAt = job.completedAt else { return nil }
        let state: String
        switch job.sync {
        case .notCompleted: return nil
        case .waiting: state = "waiting to send"
        case .sent: state = "sent"
        case .couldNotSend: state = "couldn't send"
        }
        return "Completed \(formatTime(completedAt)) · \(state)"
    }

    /// Shows the job's every change until the stream ends or the task is cancelled.
    func start() async {
        if photo == nil { photo = try? await loadJobs.photo(jobID: jobID) }
        for await snapshot in loadJobs.snapshots() {
            guard let latest = snapshot.jobs.first(where: { $0.id == jobID }) else { continue }
            // Later snapshots echo the draft back, so the field keeps what's typed, until the stored note is final.
            if job == nil || latest.completedAt != nil {
                isShowingSavedNote = true
                note = latest.note ?? ""
                isShowingSavedNote = false
            }
            job = latest
        }
    }

    /// A photo that can't be saved is dropped, and the photo area stays open for another try.
    func photoTaken(_ jpeg: Data) async {
        guard canTakePhoto else { return }
        do {
            try await attachPhoto(jobID: jobID, jpeg: jpeg)
            photo = jpeg
        } catch {}
    }

    func complete() async {
        guard canComplete else { return }
        isCompleting = true // stays set on success, until the snapshot with `completedAt` locks the screen
        await noteSave?.value // the completion freezes the stored note, so the last keystroke must be saved first
        do {
            try await completeJob(jobID: jobID)
            Task { await sendPendingWork() }
        } catch {
            isCompleting = false
        }
    }

    /// Each save waits for the one before, so the store never ends on an older draft.
    private func saveDraft() {
        noteSave = Task { [previous = noteSave, saveNote, jobID, note] in
            await previous?.value
            try? await saveNote(jobID: jobID, note: note)
        }
    }
}
