import Foundation
import Network

enum NetworkMonitor {
    /// `true` while the path is satisfied. `NWPathMonitor` reports the current path first, then every change.
    static func paths() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
        }
    }
}
