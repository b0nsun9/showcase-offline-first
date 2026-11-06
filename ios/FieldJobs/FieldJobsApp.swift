import Data
import Domain
import SwiftUI

/// The composition root: the only place that knows the Data layer.
@main
struct FieldJobsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var jobList = JobListViewModel(loadJobs: LoadJobs(repository: Self.repository),
                                                        sendPendingWork: SendPendingWork(repository: Self.repository),
                                                        formatTime: Self.formatTime)

    var body: some Scene {
        WindowGroup {
            JobListView(vm: jobList, makeDetail: Self.makeDetail)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await jobList.appBecameActive() } }
        }
    }

    /// One repository for every screen: two would open the same store twice.
    private static let repository: LiveJobRepository = {
        let config = AppConfig(info: Bundle.main.infoDictionary ?? [:])
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            return try LiveJobRepository.make(host: config.host, apiKey: config.apiKey,
                                              storeURL: support.appendingPathComponent("FieldJobs.sqlite"))
        } catch {
            // The jobs stay on disk; an app that can't save would show work it can't keep.
            fatalError("Can't open the job store: \(error)")
        }
    }()

    nonisolated private static func formatTime(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    private static func makeDetail(jobID: String) -> JobDetailViewModel {
        JobDetailViewModel(jobID: jobID, loadJobs: LoadJobs(repository: repository),
                           attachPhoto: AttachPhoto(repository: repository), saveNote: SaveNote(repository: repository),
                           completeJob: CompleteJob(repository: repository),
                           sendPendingWork: SendPendingWork(repository: repository), formatTime: formatTime)
    }
}
