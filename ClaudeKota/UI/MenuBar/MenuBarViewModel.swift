import SwiftUI
import AppKit

@Observable @MainActor
final class MenuBarViewModel {
    let appState: AppState
    let notesManager: NotesManager
    let statusService: StatusService
    var isNotesOpen = false
    private(set) var clockTick: Date = .now
    private var clockTimer: Timer?

    init(appState: AppState, notesManager: NotesManager, statusService: StatusService) {
        self.appState = appState
        self.notesManager = notesManager
        self.statusService = statusService
    }

    var statusText: String {
        switch appState.claudeSystemStatus {
        case .operational: "Canl\u{0131}"
        case .degraded: "Sorunlu"
        case .major: "Kesinti"
        case .maintenance: "Bak\u{0131}m"
        }
    }

    var statusDotColor: Color {
        switch appState.claudeSystemStatus {
        case .operational: .green
        case .degraded, .maintenance: .yellow
        case .major: .red
        }
    }

    var connectionStatusText: String {
        switch appState.connectionStatus {
        case .connected: statusText
        case .disconnected: "Ba\u{011F}lant\u{0131} yok"
        case .error(let msg): msg
        }
    }

    var connectionDotColor: Color {
        switch appState.connectionStatus {
        case .connected: statusDotColor
        case .disconnected: .gray
        case .error: .red
        }
    }

    var resetTimeText: String {
        _ = clockTick
        return MenuBarIconRenderer.formatResetTime(from: appState.sessionResetDate)
    }

    var lastUpdateText: String {
        _ = clockTick
        guard let date = appState.lastUpdateDate else { return "--" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Az \u{00F6}nce" }
        let minutes = seconds / 60
        return "Son \(minutes)dk"
    }

    var paceStatusText: String {
        switch appState.paceStatus {
        case .comfortable: "Rahat"
        case .balanced: "Dengeli"
        case .fast: "H\u{0131}zl\u{0131}"
        case .critical: "Kritik"
        case .unknown: "--"
        }
    }

    var paceStatusColor: Color {
        switch appState.paceStatus {
        case .comfortable: DT.Colors.statusGreen
        case .balanced: DT.Colors.statusOrange
        case .fast: DT.Colors.statusOrange
        case .critical: DT.Colors.statusRed
        case .unknown: .secondary
        }
    }

    var timeElapsedFraction: Double {
        _ = clockTick
        guard let resetDate = appState.sessionResetDate else { return 0 }
        let totalWindow = TimingConstants.sessionWindowDuration
        let remaining = resetDate.timeIntervalSince(Date())
        guard remaining > 0 else { return 1 }
        return 1.0 - (remaining / totalWindow)
    }

    var noteCount: Int {
        notesManager.settings.notes.count
    }

    func toggleNotes() {
        isNotesOpen.toggle()
    }

    func openStatusPage() {
        statusService.openStatusPage()
    }

    func startClockTick() {
        guard clockTimer == nil else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clockTick = .now
            }
        }
    }

    func stopClockTick() {
        clockTimer?.invalidate()
        clockTimer = nil
    }
}
