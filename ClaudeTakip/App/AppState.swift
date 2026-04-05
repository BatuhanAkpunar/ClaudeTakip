import Foundation

enum PaceStatus: String, Sendable, Comparable {
    case comfortable
    case steady
    case moderate
    case elevated
    case high
    case critical
    case unknown

    private var severity: Int {
        switch self {
        case .comfortable: 0
        case .steady: 1
        case .moderate: 2
        case .elevated: 3
        case .high: 4
        case .critical: 5
        case .unknown: -1
        }
    }

    static func < (lhs: PaceStatus, rhs: PaceStatus) -> Bool {
        lhs.severity < rhs.severity
    }
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

struct UsageSnapshot: Codable, Sendable {
    let timestamp: Date
    let usage: Double
}

@Observable @MainActor
final class AppState {
    // Auth
    var isLoggedIn: Bool = false
    var organizationId: String?
    var accountName: String?
    var planName: String?

    // Session (5-hour)
    var sessionUsage: Double = 0
    var sessionRemaining: Double = 1.0
    var sessionResetDate: Date?
    var hasLoadedUsage: Bool = false

    // Weekly (7-day)
    var weeklyUsage: Double = 0
    var weeklyResetDate: Date?

    // Sonnet-specific
    var sonnetRemaining: Double = 1.0
    var sonnetUsage: Double = 0
    var sonnetResetDate: Date?

    // Extra usage (overage billing)
    var extraUsage: ExtraUsageInfo?

    // Pacing
    var paceStatus: PaceStatus = .unknown
    var previousUsage: Double?
    var aiPacingMessage: PacingMessage?

    // Usage history (in-memory — UsageCacheStore writes to disk)
    var usageHistory: [UsageSnapshot] = []
    var weeklyUsageHistory: [UsageSnapshot] = []
    var sonnetUsageHistory: [UsageSnapshot] = []

    // Connection
    var connectionStatus: ConnectionStatus = .disconnected
    var claudeSystemStatus: SystemStatus = .operational

    // Refresh
    var lastUpdateDate: Date?
    var manualRefreshCount: Int = 0
    var refreshCooldownEnd: Date?
    var consecutiveErrors: Int = 0
}
