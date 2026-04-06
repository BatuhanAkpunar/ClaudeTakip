import Foundation
import os.log

private let logger = Logger(subsystem: "com.batuhanakpunar.ClaudeTakip", category: "AutoSession")

@MainActor
final class AutoSessionService {
    private let appState: AppState
    private let authManager: AuthManager
    private let notesManager: NotesManager
    private var checkTimer: Timer?
    private var lastAttemptDate: Date?

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

    /// Clears per-session state (used on sign-out to prevent stale cooldowns).
    func resetState() {
        lastAttemptDate = nil
    }

    /// Immediately starts a new session using the cheapest model (Haiku).
    func startSessionNow() async {
        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else { return }

        do {
            let convId = try await createConversation(sessionKey: sessionKey, orgId: orgId)
            try await sendMessage(sessionKey: sessionKey, orgId: orgId, convId: convId, model: "claude-3-5-haiku-20241022")
            try? await deleteConversation(sessionKey: sessionKey, orgId: orgId, convId: convId)
            logger.debug("[AutoSession] Immediate session started successfully")
        } catch {
            logger.debug("[AutoSession] Immediate session failed: \(type(of: error))")
        }
    }

    func checkOnLaunch() async {
        guard notesManager.settings.autoSession,
              appState.hasLoadedUsage else { return }
        await checkAndStartSession()
    }

    private func checkAndStartSession() async {
        guard notesManager.settings.autoSession else { return }

        // Trigger if: reset date expired OR no active session at all (nil after data loaded)
        if let resetDate = appState.sessionResetDate {
            guard Date() > resetDate else { return }
        } else {
            guard appState.hasLoadedUsage else { return }
        }

        // Cooldown: don't retry more than once per 3 minutes
        if let last = lastAttemptDate, Date().timeIntervalSince(last) < 180 { return }

        try? await Task.sleep(for: .seconds(TimingConstants.autoSessionDelay))

        // Re-check after delay (user may have disabled or session already refreshed)
        guard notesManager.settings.autoSession,
              let currentReset = appState.sessionResetDate,
              Date() > currentReset else { return }

        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else { return }

        lastAttemptDate = Date()

        var convId: String?
        do {
            // 1. Create a new conversation
            convId = try await createConversation(sessionKey: sessionKey, orgId: orgId)

            // 2. Send a message to trigger a new session window (Haiku = cheapest)
            guard let id = convId else { throw AutoSessionError.createFailed }
            try await sendMessage(sessionKey: sessionKey, orgId: orgId, convId: id, model: "claude-3-5-haiku-20241022")

            // Success — clear the expired reset date
            appState.sessionResetDate = nil
            logger.debug("[AutoSession] New session started successfully")
        } catch {
            logger.debug("[AutoSession] Failed: \(type(of: error))")
        }

        // Always clean up — even if sendMessage failed
        if let convId {
            try? await deleteConversation(sessionKey: sessionKey, orgId: orgId, convId: convId)
        }
    }

    // MARK: - API Calls

    private func createConversation(sessionKey: String, orgId: String) async throws -> String {
        let urlString = APIConstants.baseURL + APIConstants.conversationsPath(orgId: orgId)
        guard let url = URL(string: urlString) else { throw AutoSessionError.invalidURL }

        let convUUID = UUID().uuidString.lowercased()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "uuid": convUUID,
            "name": ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...201).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.debug("[AutoSession] Create conversation failed with status: \(code)")
            throw AutoSessionError.createFailed
        }

        return convUUID
    }

    private func sendMessage(sessionKey: String, orgId: String, convId: String, model: String? = nil) async throws {
        let urlString = APIConstants.baseURL + APIConstants.completionPath(orgId: orgId, convId: convId)
        guard let url = URL(string: urlString) else { throw AutoSessionError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "prompt": "hi",
            "timezone": TimeZone.current.identifier
        ]
        if let model {
            body["model"] = model
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.debug("[AutoSession] Send message failed with status: \(code)")
            throw AutoSessionError.messageFailed
        }
    }

    private func deleteConversation(sessionKey: String, orgId: String, convId: String) async throws {
        let urlString = APIConstants.baseURL + APIConstants.conversationsPath(orgId: orgId) + "/\(convId)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 10

        let (_, _) = try await URLSession.shared.data(for: request)
    }
}

enum AutoSessionError: Error {
    case invalidURL, createFailed, messageFailed, parseError
}
