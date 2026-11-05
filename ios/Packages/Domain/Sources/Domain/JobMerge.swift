import Foundation

public enum JobMerge {
    public static func merge(local: [Job], server: [Job]) -> [Job] {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = server.map { serverJob -> Job in
            guard let localJob = localByID[serverJob.id] else { return serverJob }
            if localJob.completedAt != nil, isUnsent(localJob) { return localJob }
            if localJob.completedAt == nil, serverJob.completedAt == nil {
                var merged = serverJob
                merged.photo = localJob.photo
                merged.note = localJob.note
                return merged
            }
            return serverJob
        }
        let serverIDs = Set(server.map(\.id))
        result += local.filter { !serverIDs.contains($0.id) && isUnsent($0) }
        return result
    }

    private static func isUnsent(_ job: Job) -> Bool { job.sync == .waiting || job.sync == .couldNotSend }
}
