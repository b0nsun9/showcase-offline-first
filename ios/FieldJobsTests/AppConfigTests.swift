@testable import FieldJobs
import Testing

@MainActor @Suite(.timeLimit(.minutes(1))) struct AppConfigTests {
    @Test func appConfigReadsInfo() {
        let config = AppConfig(info: ["APIHost": "h", "APIKey": "k"])
        #expect(config.host == "h")
        #expect(config.apiKey == "k")

        #expect(AppConfig(info: ["APIHost": "h"]).apiKey == "")
        #expect(AppConfig(info: ["APIHost": "h", "APIKey": ""]).apiKey == "")
    }
}
