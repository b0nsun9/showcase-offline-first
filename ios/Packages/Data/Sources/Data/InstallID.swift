import Foundation

public enum InstallID {
    public static func current(in defaults: UserDefaults) -> UUID {
        if let s = defaults.string(forKey: "installID"), let id = UUID(uuidString: s) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: "installID")
        return id
    }
}
