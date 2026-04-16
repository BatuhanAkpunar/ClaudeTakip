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
    static func completionPath(orgId: String, convId: String) -> String {
        "/api/organizations/\(orgId)/chat_conversations/\(convId)/completion"
    }
    static let accountPath = "/api/account"
    static let statusURL = "https://status.claude.com/api/v2/status.json"
    static let statusWebURL = "https://status.claude.com"
}

enum TimingConstants {
    static let usagePollingInterval: TimeInterval = 180       // 3 minutes
    static let statusPollingInterval: TimeInterval = 900      // 15 minutes
    static let manualRefreshCooldown: TimeInterval = 120      // 2 minutes
    static let maxManualRefreshes: Int = 3
    static let autoSessionDelay: TimeInterval = 30            // 30 seconds
    static let retryDelay: TimeInterval = 30                  // 30 seconds
    static let maxConsecutiveErrors: Int = 5
    static let sessionWindowDuration: TimeInterval = 5 * 3600 // 5 hours
    static let weeklyWindowDuration: TimeInterval = 7 * 86400 // 7 days
}

enum PacingConstants {
    // Position deviation thresholds (relative to ideal line)
    static let steadyPositionThreshold: Double = 0.03
    static let moderatePositionThreshold: Double = 0.08
    static let elevatedPositionThreshold: Double = 0.15
    static let highPositionThreshold: Double = 0.25
    static let criticalPositionThreshold: Double = 0.40

    // Rate multiplier thresholds (relative to ideal speed)
    static let steadyRateThreshold: Double = 1.0
    static let moderateRateThreshold: Double = 1.3
    static let elevatedRateThreshold: Double = 1.8
    static let highRateThreshold: Double = 2.5
    static let criticalRateThreshold: Double = 4.0

    static let criticalRemainingThreshold: Double = 0.10
    static let minRemainingMinutes: Double = 10
    static let maxFastAlertPerSession: Int = 2
}

enum GroqConstants {
    static let baseURL = "https://claudetakip.vercel.app/api/ai-pacing"
    static let model = "meta-llama/llama-4-scout-17b-16e-instruct"
    static let debounceInterval: TimeInterval = 30
    static let staleCacheInterval: TimeInterval = 3600 // 1 hour
    static let maxConsecutiveErrors: Int = 5
}

enum UserDefaultsKeys {
    static let lastSessionOverflowDate = "lastSessionOverflowDate"
}

enum KeychainConstants {
    static let service = "com.batuhanakpunar.ClaudeTakip"
    static let sessionKeyAccount = "sessionKey"
    static let orgIdAccount = "organizationId"
    static let accountNameAccount = "accountName"
    static let planNameAccount = "planName"
    static let accountDetailsAccount = "accountDetails"
}
