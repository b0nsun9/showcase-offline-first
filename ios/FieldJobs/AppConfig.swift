import Foundation

/// The API host and key that the build writes into Info.plist from the xcconfig files.
struct AppConfig {
    let host: String
    let apiKey: String

    init(info: [String: Any]) {
        host = info["APIHost"] as? String ?? ""
        apiKey = info["APIKey"] as? String ?? ""
    }
}
