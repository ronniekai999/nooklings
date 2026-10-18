import XCTest
@testable import Byte

final class PreferencesTests: XCTestCase {
    func testSourceLaunchMigrationPreservesDestinationAndDoesNotResurrectRemovedValues() {
        let suite = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("cat", forKey: "byte.companion")
        let newer: [String: Any] = ["byte.model": "new-model", "byte.sounds": false]
        let older: [String: Any] = ["byte.model": "old-model", "byte.companion": "trex",
                                   "byte.provider": "chatGPT", "byte.pinX": 123.0,
                                   "byte.chatGPT.hostID": "existing-host", "NSUnrelatedPreference": "ignore"]
        AppPreferences.migrate(sources: [newer, older], into: defaults)
        XCTAssertEqual(defaults.string(forKey: "byte.model"), "new-model")
        XCTAssertEqual(defaults.string(forKey: "byte.companion"), "cat")
        XCTAssertEqual(defaults.string(forKey: "byte.provider"), "chatGPT")
        XCTAssertEqual(defaults.double(forKey: "byte.pinX"), 123)
        XCTAssertEqual(defaults.string(forKey: "byte.chatGPT.hostID"), "existing-host")
        XCTAssertFalse(defaults.bool(forKey: "byte.sounds"))
        XCTAssertNil(defaults.object(forKey: "NSUnrelatedPreference"))
        defaults.removeObject(forKey: "byte.provider")
        AppPreferences.migrate(sources: [older], into: defaults)
        XCTAssertNil(defaults.object(forKey: "byte.provider"))
    }
}
