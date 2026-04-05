import Foundation
import WebKit

@MainActor
final class AuthManager {
    private let keychain = KeychainService()
    private let appState: AppState

    // In-memory cache — only accesses Keychain on login/logout/launch
    private var cachedSessionKey: String?

    init(appState: AppState) {
        self.appState = appState
    }

    func checkExistingSession() async {
        guard let sessionKey = try? keychain.retrieve(key: KeychainConstants.sessionKeyAccount),
              let orgId = try? keychain.retrieve(key: KeychainConstants.orgIdAccount) else {
            appState.isLoggedIn = false
            return
        }
        cachedSessionKey = sessionKey
        appState.organizationId = orgId
        appState.accountName = try? keychain.retrieve(key: KeychainConstants.accountNameAccount)
        appState.planName = try? keychain.retrieve(key: KeychainConstants.planNameAccount)
        appState.isLoggedIn = true
        appState.connectionStatus = .connected
    }

    func handleLoginCookie(_ sessionKey: String) async throws {
        try keychain.save(key: KeychainConstants.sessionKeyAccount, value: sessionKey)
        cachedSessionKey = sessionKey

        let info = try await fetchOrganizationInfo(sessionKey: sessionKey)
        try keychain.save(key: KeychainConstants.orgIdAccount, value: info.id)
        if let name = info.name {
            try keychain.save(key: KeychainConstants.accountNameAccount, value: name)
        }
        if let plan = info.plan {
            try keychain.save(key: KeychainConstants.planNameAccount, value: plan)
        }

        appState.organizationId = info.id
        appState.accountName = info.name
        appState.planName = info.plan
        appState.isLoggedIn = true
        appState.connectionStatus = .connected
    }

    func signOut() {
        cachedSessionKey = nil
        try? keychain.delete(key: KeychainConstants.sessionKeyAccount)
        try? keychain.delete(key: KeychainConstants.orgIdAccount)
        try? keychain.delete(key: KeychainConstants.accountNameAccount)
        try? keychain.delete(key: KeychainConstants.planNameAccount)

        // Auth
        appState.isLoggedIn = false
        appState.organizationId = nil
        appState.accountName = nil
        appState.planName = nil

        // Session
        appState.sessionUsage = 0
        appState.sessionRemaining = 1.0
        appState.sessionResetDate = nil
        appState.hasLoadedUsage = false

        // Weekly
        appState.weeklyUsage = 0
        appState.weeklyResetDate = nil

        // Models
        appState.sonnetUsage = 0
        appState.sonnetRemaining = 1.0
        appState.sonnetResetDate = nil
        appState.extraUsage = nil

        // Pacing
        appState.paceStatus = .unknown
        appState.previousUsage = nil
        appState.aiPacingMessage = nil
        appState.isAIUnavailable = false

        // Connection / refresh
        appState.connectionStatus = .disconnected
        appState.lastUpdateDate = nil
        appState.consecutiveErrors = 0
        appState.manualRefreshCount = 0
        appState.refreshCooldownEnd = nil

        clearWebCookies()
    }

    private func clearWebCookies() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let claudeRecords = records.filter { $0.displayName.contains("claude") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: claudeRecords) {}
        }
    }

    func getSessionKey() -> String? {
        if let cached = cachedSessionKey { return cached }
        // Fallback: cache miss (should not happen, but just in case)
        let key = try? keychain.retrieve(key: KeychainConstants.sessionKeyAccount)
        cachedSessionKey = key
        return key
    }

    private func fetchOrganizationInfo(sessionKey: String) async throws -> (id: String, name: String?, plan: String?) {
        guard let url = URL(string: APIConstants.baseURL + APIConstants.organizationsPath) else {
            throw AuthError.organizationFetchFailed
        }
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.organizationFetchFailed
        }

        let orgs = try JSONDecoder().decode([Organization].self, from: data)
        guard let org = orgs.first else {
            throw AuthError.noOrganizationFound
        }

        let plan = Self.detectPlan(from: data)
        return (org.uuid, org.name, plan)
    }

    private static func detectPlan(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let org = json.first else { return nil }

        // Collect all string values recursively from the response
        var allStrings: [String] = []
        collectStrings(from: org, into: &allStrings)

        // Check combined text for specific plan identifiers (most specific first)
        let combined = allStrings.joined(separator: " ").lowercased()
        if combined.contains("max_20") || combined.contains("max20") { return "Max 20" }
        if combined.contains("max_5") || combined.contains("max5") { return "Max 5" }
        if combined.contains("enterprise") { return "Enterprise" }
        if combined.contains("team") { return "Team" }

        // Individual value check for "pro"/"free" to avoid false positives
        for str in allStrings {
            let lower = str.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "pro" || lower.hasSuffix("_pro") || lower.hasPrefix("pro_")
                || lower.contains("pro_plan") || lower.contains("claude_pro") {
                return "Pro"
            }
            if lower == "free" || lower.hasSuffix("_free") || lower.hasPrefix("free_")
                || lower.contains("free_plan") || lower.contains("free_tier") {
                return "Free"
            }
        }

        return nil
    }

    private static func collectStrings(from value: Any, into strings: inout [String]) {
        if let str = value as? String {
            strings.append(str)
        } else if let dict = value as? [String: Any] {
            for (_, val) in dict {
                collectStrings(from: val, into: &strings)
            }
        } else if let arr = value as? [Any] {
            for item in arr {
                collectStrings(from: item, into: &strings)
            }
        }
    }
}

enum AuthError: Error, LocalizedError {
    case organizationFetchFailed
    case noOrganizationFound
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .organizationFetchFailed: String(localized: "Failed to fetch organization info", bundle: .app)
        case .noOrganizationFound: String(localized: "No organization found in the account", bundle: .app)
        case .sessionExpired: String(localized: "Session expired, please sign in again", bundle: .app)
        }
    }
}

private struct Organization: Codable {
    let uuid: String
    let name: String?
}
