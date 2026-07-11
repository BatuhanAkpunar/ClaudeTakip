import Testing
import SwiftUI
import AppKit
@testable import ClaudeTakip

/// Renders the real MenuBarView with realistic fake data into PNGs so design
/// changes can be SEEN and judged during development. Not a pass/fail pixel
/// test; it only fails if rendering breaks.
@MainActor
@Suite struct SnapshotHarnessTests {

    private func makeViewModel(darkMode: Bool) -> MenuBarViewModel {
        // Isolated defaults: the real app domain may carry an explicit
        // darkMode that would override the window appearance via
        // .preferredColorScheme, breaking the dark render.
        let suiteName = "ClaudeTakip.SnapshotHarness"
        let store = UserDefaults(suiteName: suiteName)!
        store.removePersistentDomain(forName: suiteName)
        let notesManager = NotesManager(store: store)
        notesManager.updateSettings {
            $0.darkMode = darkMode
            $0.aiRecommendation = false
        }

        let appState = AppState()
        appState.isLoggedIn = true
        appState.hasLoadedUsage = true
        appState.planName = "Pro"
        appState.sessionUsage = 0.63
        appState.weeklyUsage = 0.41
        appState.sonnetUsage = 1.0
        appState.modelLimitName = "Fable"
        appState.sessionResetDate = Date().addingTimeInterval(2 * 3600 + 14 * 60)
        appState.weeklyResetDate = Date().addingTimeInterval(3 * 86400 + 4 * 3600)
        appState.sonnetResetDate = Date().addingTimeInterval(3 * 86400)
        appState.lastUpdateDate = Date().addingTimeInterval(-3 * 60)
        appState.claudeSystemStatus = .operational
        appState.connectionStatus = .connected
        appState.extraUsage = ExtraUsageInfo(
            isEnabled: true,
            monthlyLimit: 2500,
            usedCredits: 420,
            utilization: 17,
            currentBalance: nil,
            autoReload: false
        )

        let sessionStart = appState.sessionResetDate!.addingTimeInterval(-5 * 3600)
        appState.usageHistory = (0...11).map { i in
            let t = sessionStart.addingTimeInterval(Double(i) * 14 * 60)
            let u = min(0.63, Double(i) * 0.06 + (i > 6 ? 0.05 : 0))
            return UsageSnapshot(timestamp: t, usage: u)
        }
        let weekStart = appState.weeklyResetDate!.addingTimeInterval(-7 * 86400)
        appState.weeklyUsageHistory = (0...16).map { i in
            let t = weekStart.addingTimeInterval(Double(i) * 6 * 3600)
            return UsageSnapshot(timestamp: t, usage: min(0.41, Double(i) * 0.028))
        }

        return MenuBarViewModel(
            appState: appState,
            notesManager: notesManager,
            statusService: StatusService(appState: appState)
        )
    }

    private func snapshot(appearance: NSAppearance.Name, to path: String, limitsPage: Int? = nil, collapseChart: Bool = false) throws {
        let vm = makeViewModel(darkMode: appearance == .darkAqua)
        let view = MenuBarView(
            viewModel: vm,
            onRefresh: {},
            onSignOut: {},
            onQuit: {},
            onStartSession: nil,
            onCheckUpdate: nil,
            revealImmediately: true,
            limitsPageForSnapshot: limitsPage,
            collapseChartForSnapshot: collapseChart
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 900)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.orderBack(nil)

        // Pump long enough for the value-reveal task (300 ms delay + 0.8 s
        // ease) to fully settle.
        for _ in 0..<70 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let size = NSSize(width: max(fitting.width, 320), height: max(fitting.height, 400))
        window.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("no bitmap rep")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("no png data")
            return
        }
        try png.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }

    @Test func renderLightSnapshot() throws {
        try snapshot(appearance: .aqua, to: "/tmp/claudetakip-snap-light.png")
    }

    @Test func renderDarkSnapshot() throws {
        try snapshot(appearance: .darkAqua, to: "/tmp/claudetakip-snap-dark.png")
    }

    @Test func renderRingsPageSnapshot() throws {
        try snapshot(appearance: .aqua, to: "/tmp/claudetakip-snap-rings.png", limitsPage: 1)
    }

    @Test func renderRatePageSnapshot() throws {
        try snapshot(appearance: .aqua, to: "/tmp/claudetakip-snap-rate.png", limitsPage: 2)
    }

    @Test func renderCollapsedChartSnapshot() throws {
        try snapshot(appearance: .aqua, to: "/tmp/claudetakip-snap-collapsed.png", collapseChart: true)
    }
}
