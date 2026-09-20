import Combine
import Foundation
import Sparkle

enum UpdatePreferences {
    static func migrateToOwnedRepository(_ defaults: UserDefaults) {
        let migrationKey = "codexVitalsOwnedRepositoryUpdatesV1"
        guard !defaults.bool(forKey: migrationKey) else { return }
        // The owner requested automatic updates from this repository. Migrate
        // once, then preserve any later choices made in Settings.
        defaults.removeObject(forKey: "SUFeedURL")
        defaults.set(true, forKey: "SUEnableAutomaticChecks")
        defaults.set(true, forKey: "SUAutomaticallyUpdate")
        defaults.set(true, forKey: migrationKey)
    }
}

@MainActor
final class RepositoryUpdateDelegate: NSObject, SPUUpdaterDelegate {
    // Pin the repository even if an older installation saved another feed.
    func feedURLString(for updater: SPUUpdater) -> String? {
        AppInfo.updateFeedURL.absoluteString
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    let controller: SPUStandardUpdaterController
    private let updateDelegate = RepositoryUpdateDelegate()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyInstallsUpdates = false

    private var cancellables = Set<AnyCancellable>()

    init(startingUpdater: Bool = true) {
        if startingUpdater {
            UpdatePreferences.migrateToOwnedRepository(.standard)
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: updateDelegate,
            userDriverDelegate: nil
        )

        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        refreshSettings()

        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        refreshSettings()
    }

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
        refreshSettings()
    }

    func refreshSettings() {
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyInstallsUpdates = controller.updater.automaticallyDownloadsUpdates
    }
}
