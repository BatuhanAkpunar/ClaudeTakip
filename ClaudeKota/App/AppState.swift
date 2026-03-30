import Foundation

enum PaceStatus: String, Sendable {
    case comfortable
    case balanced
    case fast
    case critical
    case unknown
}

enum ConnectionStatus: Sendable, Equatable {
    case connected
    case disconnected
    case error(String)
}

enum SystemStatus: String, Sendable {
    case operational
    case degraded
    case major
    case maintenance
}

@Observable @MainActor
final class AppState {
    // Auth
    var isLoggedIn: Bool = false
    var organizationId: String?

    // Session (5 saatlik)
    var sessionUsage: Double = 0
    var sessionRemaining: Double = 1.0
    var sessionResetDate: Date?

    // Weekly (7 gunluk)
    var weeklyUsage: Double = 0
    var weeklyResetDate: Date?

    // Pacing
    var paceStatus: PaceStatus = .unknown
    var previousUsage: Double?

    // Connection
    var connectionStatus: ConnectionStatus = .disconnected
    var claudeSystemStatus: SystemStatus = .operational

    // Refresh
    var lastUpdateDate: Date?
    var manualRefreshCount: Int = 0
    var refreshCooldownEnd: Date?
    var consecutiveErrors: Int = 0
}
