import Foundation

@MainActor
final class AutoSessionService {
    private let appState: AppState
    private let authManager: AuthManager
    private let notesManager: NotesManager
    private var checkTimer: Timer?

    init(appState: AppState, authManager: AuthManager, notesManager: NotesManager) {
        self.appState = appState
        self.authManager = authManager
        self.notesManager = notesManager
    }

    func startMonitoring() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndStartSession()
            }
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkAndStartSession() async {
        guard notesManager.settings.autoSession,
              let resetDate = appState.sessionResetDate,
              Date() > resetDate else { return }

        try? await Task.sleep(for: .seconds(TimingConstants.autoSessionDelay))

        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else { return }

        do {
            let convId = try await createConversation(sessionKey: sessionKey, orgId: orgId)
            try await deleteConversation(sessionKey: sessionKey, orgId: orgId, convId: convId)
            appState.sessionResetDate = nil
        } catch {
            // Hata olursa sessizce devam et
        }
    }

    private func createConversation(sessionKey: String, orgId: String) async throws -> String {
        let urlString = APIConstants.baseURL + APIConstants.conversationsPath(orgId: orgId)
        guard let url = URL(string: urlString) else { throw AutoSessionError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = """
        {"message":"hi"}
        """.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AutoSessionError.createFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let convId = json["uuid"] as? String else {
            throw AutoSessionError.parseError
        }
        return convId
    }

    private func deleteConversation(sessionKey: String, orgId: String, convId: String) async throws {
        let urlString = APIConstants.baseURL + APIConstants.conversationsPath(orgId: orgId) + "/\(convId)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // Conversation silinmeden kaldi -- kritik degil
        }
    }
}

enum AutoSessionError: Error {
    case invalidURL, createFailed, parseError
}
