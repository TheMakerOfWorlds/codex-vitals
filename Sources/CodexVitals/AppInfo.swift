import Foundation

enum AppInfo {
    static let name = "Codex Vitals"
    static let homepageURL = URL(string: "https://ramterstudio.com/codex-vitals/")!
    static let repositoryURL = URL(string: "https://github.com/Joowonoil/Codex-Vitals")!
    static let releasesURL = URL(string: "https://github.com/Joowonoil/Codex-Vitals/releases")!
    static let keystoneRepositoryURL = URL(string: "https://github.com/KeystoneScience/codex-vitals")!

    static var isPersonalBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CodexVitalsPersonalBuild") as? Bool ?? false
    }

    static var versionText: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return "Unknown"
        }
        let label = version.hasPrefix("v") ? version : "v\(version)"
        return isPersonalBuild ? "\(label) · Personal" : label
    }
}
