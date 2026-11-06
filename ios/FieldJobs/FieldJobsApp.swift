import Data
import Domain
import SwiftUI

/// The composition root: the only place that knows the Data layer.
@main
struct FieldJobsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var jobList = Self.makeJobList()

    var body: some Scene {
        WindowGroup {
            JobListView(vm: jobList)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await jobList.appBecameActive() } }
        }
    }

    private static func makeJobList() -> JobListViewModel {
        let config = AppConfig(info: Bundle.main.infoDictionary ?? [:])
        let repository: LiveJobRepository
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            repository = try LiveJobRepository.make(host: config.host, apiKey: config.apiKey,
                                                    storeURL: support.appendingPathComponent("FieldJobs.sqlite"))
        } catch {
            // The jobs stay on disk; an app that can't save would show work it can't keep.
            fatalError("Can't open the job store: \(error)")
        }
        return JobListViewModel(loadJobs: LoadJobs(repository: repository),
                                sendPendingWork: SendPendingWork(repository: repository),
                                formatTime: { $0.formatted(date: .omitted, time: .shortened) })
    }
}
