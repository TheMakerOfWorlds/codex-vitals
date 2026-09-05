#if DEBUG
import AppKit
import SwiftUI
import UserNotifications

@MainActor
enum SanitizedScreenshotRenderer {
    static func render() throws {
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dark = CommandLine.arguments.contains("--dark")
        let credits = CommandLine.arguments.contains("--credits")
        let filename = credits ? (dark ? "credits-dark.png" : "credits.png") : (dark ? "screenshot-dark.png" : "screenshot.png")
        let output = repository.appendingPathComponent("docs/" + filename)
        let viewModel = UsageViewModel(resetNotificationService: ScreenshotNotificationService(), loadPersistedState: false)
        configure(viewModel)
        let size = credits ? NSSize(width: 400, height: 140) : NSSize(width: ContentView.preferredWidth, height: 526)
        let rootView = Group {
            if credits {
                VStack(alignment: .leading, spacing: 14) {
                    Text(AppInfo.name).font(.system(size: 17, weight: .semibold))
                    AppCreditsView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(24)
                .background(Theme.appBackground)
            } else {
                SanitizedProductScreenshot(viewModel: viewModel)
            }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: output, options: .atomic)
        window.close()
    }

    private static func configure(_ viewModel: UsageViewModel) {
        let codexKeys = ["codex-primary", "codex-research", "codex-team"]
        viewModel.accounts = [
            account(
                id: "alex@example.com|sample-1",
                profileKey: codexKeys[0],
                email: "alex@example.com",
                alias: "Personal",
                workspace: "pro",
                plan: "pro",
                fiveHour: 78,
                weekly: 64,
                fiveHourReset: 9_800,
                weeklyReset: 345_600,
                provider: .codex,
                availableResets: 2,
                resetExpirations: [
                    sampleDate("2026-09-21T23:09:00Z"),
                    sampleDate("2026-10-18T16:30:00Z"),
                ],
                planDaysRemaining: 5
            ),
            account(
                id: "research01@example.com|sample-2",
                profileKey: codexKeys[1],
                email: "research01@example.com",
                alias: "Research One",
                workspace: "Lab",
                plan: "pro_lite",
                fiveHour: 100,
                weekly: 92,
                fiveHourReset: 14_400,
                weeklyReset: 432_000,
                provider: .codex,
                availableResets: 0,
                resetExpirations: [],
                planDaysRemaining: 23,
                singleWindowSeconds: 30 * 24 * 60 * 60
            ),
            account(
                id: "team@example.com|sample-3",
                profileKey: codexKeys[2],
                email: "team@example.com",
                alias: "Shared Workspace",
                workspace: "Business",
                plan: "team",
                fiveHour: 0,
                weekly: 0,
                fiveHourReset: 7_200,
                weeklyReset: 518_400,
                provider: .codex,
                availableResets: 1,
                resetExpirations: [sampleDate("2027-03-21T18:45:00Z")],
                planDaysRemaining: 1
            ),
            account(
                id: "claude-native:sample-1",
                profileKey: nil,
                email: "claude@example.com",
                alias: "Claude Main",
                workspace: "Claude",
                plan: "Max 5x",
                fiveHour: 81,
                weekly: 73,
                fiveHourReset: 12_600,
                weeklyReset: 302_400,
                provider: .claude,
                providerProfileID: "claude-sample-1",
                providerIsActive: true,
                fable: 60
            ),
            account(
                id: "claude-native:sample-2",
                profileKey: nil,
                email: "paper@example.com",
                alias: "Paper Agent",
                workspace: "Research",
                plan: "Pro",
                fiveHour: 100,
                weekly: 98,
                fiveHourReset: 16_200,
                weeklyReset: 475_200,
                provider: .claude,
                providerProfileID: "claude-sample-2"
            ),
        ]
        viewModel.codexLoginStatus = CodexLoginStatus(
            accountIDs: [],
            sourceProfileKeys: Set(codexKeys),
            emailsWithoutAccountID: []
        )
        viewModel.isCodexInstalled = true
        viewModel.activeCodexProfileKey = codexKeys[0]
        viewModel.searchText = ""
    }

    private static func sampleDate(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw) ?? Date(timeIntervalSince1970: 0)
    }

    private static func account(
        id: String,
        profileKey: String?,
        email: String,
        alias: String,
        workspace: String,
        plan: String,
        fiveHour: Double,
        weekly: Double,
        fiveHourReset: TimeInterval,
        weeklyReset: TimeInterval,
        provider: AccountProvider,
        availableResets: Int? = nil,
        resetExpirations: [Date]? = nil,
        providerProfileID: String? = nil,
        providerIsActive: Bool = false,
        fable: Double? = nil,
        planDaysRemaining: Int? = nil,
        singleWindowSeconds: Double? = nil
    ) -> Account {
        let windows: [QuotaWindow]
        if let singleWindowSeconds {
            windows = [
                QuotaWindow(
                    limitSeconds: singleWindowSeconds,
                    remainingPercent: weekly,
                    resetAfterSeconds: weeklyReset
                )
            ]
        } else {
            windows = [
                QuotaWindow(
                    limitSeconds: QuotaWindow.fiveHourSeconds,
                    remainingPercent: fiveHour,
                    resetAfterSeconds: fiveHourReset
                ),
                QuotaWindow(
                    limitSeconds: QuotaWindow.weeklySeconds,
                    remainingPercent: weekly,
                    resetAfterSeconds: weeklyReset
                ),
            ]
        }

        return Account(
            id: id,
            profileKey: profileKey,
            email: email,
            alias: alias,
            workspace: workspace,
            plan: plan,
            sessionFree: fiveHour,
            weeklyFree: weekly,
            sessionResetSeconds: fiveHourReset,
            weeklyResetSeconds: weeklyReset,
            quotaWindows: windows,
            availableResetCount: availableResets,
            bankedResetExpirations: resetExpirations,
            fableQuotaWindow: fable.map {
                QuotaWindow(
                    limitSeconds: QuotaWindow.weeklySeconds,
                    remainingPercent: $0,
                    resetAfterSeconds: 388_800
                )
            },
            planRenewalDate: planDaysRemaining.flatMap {
                Calendar.current.date(byAdding: .day, value: $0, to: Date())
            },
            planCycleKind: planDaysRemaining == nil ? nil : .renewal,
            hasError: false,
            errorMessage: nil,
            provider: provider,
            providerProfileID: providerProfileID,
            providerIsActive: providerIsActive,
            providerStatus: "ok"
        )
    }
}

private final class ScreenshotNotificationService: UsageResetNotifying {
    func requestAuthorization() async -> Bool { false }
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func deliver(events: [UsageResetEvent]) async {}
}

private struct SanitizedProductScreenshot: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(vm: viewModel, isShowingSettings: .constant(false))
            AccountListView(vm: viewModel)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            Spacer(minLength: 0)
        }
        .frame(width: ContentView.preferredWidth, height: 526)
        .background(Theme.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
#endif
