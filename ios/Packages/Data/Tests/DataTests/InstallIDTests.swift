import Foundation
import Testing
@testable import Data

struct InstallIDTests {
    func suite() -> UserDefaults {
        let name = "InstallIDTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func installIDIsStable() {
        let d = suite()
        #expect(InstallID.current(in: d) == InstallID.current(in: d))
    }

    @Test func installIDIsStoredUnderKey() {
        let d = suite()
        let id = InstallID.current(in: d)
        #expect(d.string(forKey: "installID") == id.uuidString)
    }
}
