import Foundation

/// One identity for bundled apps and `swift run`, including upgrades from Byte.
enum AppPreferences {
    static let domain = "com.ronnie.byte"
    static let shared: UserDefaults = {
        let destination = UserDefaults(suiteName: domain)!
        let sources = [ProcessInfo.processInfo.processName, "Nooklings", "Byte"]
            .filter { $0 != domain }
            .compactMap { UserDefaults.standard.persistentDomain(forName: $0) }
        migrate(sources: sources, into: destination)
        return destination
    }()

    static func migrate(sources: [[String: Any]], into destination: UserDefaults) {
        let marker = "byte.stablePreferencesMigrated"
        guard !destination.bool(forKey: marker) else { return }
        for source in sources {
            for (key, value) in source where key.hasPrefix("byte.") && key != marker {
                if destination.object(forKey: key) == nil { destination.set(value, forKey: key) }
            }
        }
        destination.set(true, forKey: marker)
    }
}
