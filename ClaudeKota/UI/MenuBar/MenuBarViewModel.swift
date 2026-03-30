import SwiftUI
import AppKit

@Observable @MainActor
final class MenuBarViewModel {
    let appState: AppState
    let notesManager: NotesManager
    let statusService: StatusService
    var isNotesOpen = false

    init(appState: AppState, notesManager: NotesManager, statusService: StatusService) {
        self.appState = appState
        self.notesManager = notesManager
        self.statusService = statusService
    }

    var statusText: String {
        switch appState.claudeSystemStatus {
        case .operational: "Canli"
        case .degraded: "Sorunlu"
        case .major: "Kesinti"
        case .maintenance: "Bakim"
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
        case .disconnected: "Baglanti yok"
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
        MenuBarIconRenderer.formatResetTime(from: appState.sessionResetDate)
    }

    var lastUpdateText: String {
        guard let date = appState.lastUpdateDate else { return "--" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Az once" }
        let minutes = seconds / 60
        return "Son \(minutes)dk"
    }

    var paceStatusText: String {
        switch appState.paceStatus {
        case .comfortable: "Rahat"
        case .balanced: "Dengeli"
        case .fast: "Hizli"
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
}
