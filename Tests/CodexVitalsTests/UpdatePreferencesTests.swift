import XCTest
@testable import CodexVitals

final class UpdatePreferencesTests: XCTestCase {
    func testRepositoryMigrationEnablesUpdatesAndClearsLegacyFeed() {
        let name = "CodexVitalsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://example.com/legacy.xml", forKey: "SUFeedURL")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        defaults.set(false, forKey: "SUAutomaticallyUpdate")
        UpdatePreferences.migrateToOwnedRepository(defaults)
        XCTAssertNil(defaults.object(forKey: "SUFeedURL"))
        XCTAssertTrue(defaults.bool(forKey: "SUEnableAutomaticChecks"))
        XCTAssertTrue(defaults.bool(forKey: "SUAutomaticallyUpdate"))
    }

    func testLaterUserChoicesSurviveAnotherLaunch() {
        let name = "CodexVitalsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        UpdatePreferences.migrateToOwnedRepository(defaults)
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        defaults.set(false, forKey: "SUAutomaticallyUpdate")
        UpdatePreferences.migrateToOwnedRepository(defaults)
        XCTAssertFalse(defaults.bool(forKey: "SUEnableAutomaticChecks"))
        XCTAssertFalse(defaults.bool(forKey: "SUAutomaticallyUpdate"))
    }
}
