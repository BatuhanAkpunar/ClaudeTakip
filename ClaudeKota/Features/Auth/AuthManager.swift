import Foundation
import WebKit

@MainActor
final class AuthManager {
    private let keychain = KeychainService()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func checkExistingSession() async {
        guard let _ = try? keychain.retrieve(key: KeychainConstants.sessionKeyAccount),
              let orgId = try? keychain.retrieve(key: KeychainConstants.orgIdAccount) else {
            appState.isLoggedIn = false
            return
        }
        appState.organizationId = orgId
        appState.isLoggedIn = true
        appState.connectionStatus = .connected
    }

    func handleLoginCookie(_ sessionKey: String) async throws {
        try keychain.save(key: KeychainConstants.sessionKeyAccount, value: sessionKey)

        let orgId = try await fetchOrganizationId(sessionKey: sessionKey)
        try keychain.save(key: KeychainConstants.orgIdAccount, value: orgId)

        appState.organizationId = orgId
        appState.isLoggedIn = true
        appState.connectionStatus = .connected
    }

    func signOut() {
        try? keychain.delete(key: KeychainConstants.sessionKeyAccount)
        try? keychain.delete(key: KeychainConstants.orgIdAccount)
        appState.isLoggedIn = false
        appState.organizationId = nil
        appState.sessionUsage = 0
        appState.sessionRemaining = 1.0
        appState.weeklyUsage = 0
        appState.paceStatus = .unknown
        appState.connectionStatus = .disconnected
        appState.previousUsage = nil
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
        try? keychain.retrieve(key: KeychainConstants.sessionKeyAccount)
    }

    private func fetchOrganizationId(sessionKey: String) async throws -> String {
        let url = URL(string: APIConstants.baseURL + APIConstants.organizationsPath)!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.organizationFetchFailed
        }

        let orgs = try JSONDecoder().decode([Organization].self, from: data)
        guard let orgId = orgs.first?.uuid else {
            throw AuthError.noOrganizationFound
        }
        return orgId
    }
}

enum AuthError: Error, LocalizedError {
    case organizationFetchFailed
    case noOrganizationFound
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .organizationFetchFailed: "Organizasyon bilgisi alinamadi"
        case .noOrganizationFound: "Hesapta organizasyon bulunamadi"
        case .sessionExpired: "Oturum suresi doldu, tekrar giris yap"
        }
    }
}

private struct Organization: Codable {
    let uuid: String
}
