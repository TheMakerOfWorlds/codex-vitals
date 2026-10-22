import XCTest
@testable import CodexVitals

final class UpdatePreferencesTests: XCTestCase {
    func testAgentVitalsRenamePreservesExistingUpdateIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Support/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, AppInfo.name)
        XCTAssertEqual(plist["CFBundleName"] as? String, "Agent Vitals")
        // Existing installations, login items, preferences, and signed updates
        // must continue to recognize this as the same app after the rename.
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "app.codexvitals.menubar")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "CodexVitals")
        XCTAssertEqual(plist["SUFeedURL"] as? String,
            "https://raw.githubusercontent.com/TheMakerOfWorlds/codex-vitals/main/updates/appcast.xml")
        XCTAssertEqual(plist["SUPublicEDKey"] as? String, "vnw3TXixd1tWcKZnvl+LoEhAANTq2OQKBaEyegeycmI=")
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
    }

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
