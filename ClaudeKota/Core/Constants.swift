import Foundation

enum APIConstants {
    static let baseURL = "https://claude.ai"
    static let organizationsPath = "/api/organizations"
    static func usagePath(orgId: String) -> String {
        "/api/organizations/\(orgId)/usage"
    }
    static func conversationsPath(orgId: String) -> String {
        "/api/organizations/\(orgId)/chat_conversations"
    }
    static let statusURL = "https://status.claude.com/api/v2/status.json"
    static let statusWebURL = "https://status.claude.com"
}

enum TimingConstants {
    static let usagePollingInterval: TimeInterval = 180       // 3 dakika
    static let statusPollingInterval: TimeInterval = 900      // 15 dakika
    static let manualRefreshCooldown: TimeInterval = 120      // 2 dakika
    static let maxManualRefreshes: Int = 3
    static let autoSessionDelay: TimeInterval = 30            // 30 saniye
    static let retryDelay: TimeInterval = 30                  // 30 saniye
    static let maxConsecutiveErrors: Int = 5
    static let sessionWindowDuration: TimeInterval = 5 * 3600 // 5 saat
    static let weeklyWindowDuration: TimeInterval = 7 * 86400 // 7 gun
}

enum PacingConstants {
    static let balancedThreshold: Double = 1.5
    static let fastThreshold: Double = 2.5
    static let criticalRemainingThreshold: Double = 0.10
    static let minRemainingMinutes: Double = 10
    static let maxFastAlertPerSession: Int = 2
}

enum KeychainConstants {
    static let service = "com.batuhanakpunar.ClaudeKota"
    static let sessionKeyAccount = "sessionKey"
    static let orgIdAccount = "organizationId"
}

enum NoteConstants {
    static let maxNotes: Int = 50
    static let maxTitleLength: Int = 100
    static let maxContentLength: Int = 500
}
