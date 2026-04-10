import Foundation
import os.log

private let logger = Logger(subsystem: "com.batuhanakpunar.ClaudeTakip", category: "AutoSession")

@MainActor
final class AutoSessionService {
    private let appState: AppState
    private let authManager: AuthManager
    private let notesManager: NotesManager
    private var pingTask: Task<Void, Never>?
    private var isSonnetPingInFlight = false
    var onPingCompleted: (() async -> Void)?

    private let pingInterval: TimeInterval = 600 // 10 minutes
    private let sonnetPingMinInterval: TimeInterval = 3600 // 1 hour throttle
    private let lastSonnetPingKey = "lastSonnetPingDate"

    init(appState: AppState, authManager: AuthManager, notesManager: NotesManager) {
        self.appState = appState
        self.authManager = authManager
        self.notesManager = notesManager
    }

    // MARK: - Start / Stop

    func startPolling() {
        stopMonitoring()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pingInterval ?? 600))
                guard let self, !Task.isCancelled else { return }
                guard notesManager.settings.autoSession else { continue }
                NSLog("[AutoSession] Timer fired, calling ping")
                await ping(model: "claude-haiku-4-5-20251001", label: "Haiku")
            }
        }
        NSLog("[AutoSession] Polling started (every %ds)", Int(pingInterval))
    }

    func stopMonitoring() {
        pingTask?.cancel()
        pingTask = nil
    }

    func resetState() {
        stopMonitoring()
    }

    // MARK: - Manual Start (UI button)

    func startSessionNow() async {
        await ping(model: "claude-haiku-4-5-20251001", label: "Haiku")
    }

    // MARK: - Sonnet Auto-Restart

    /// Sends a single "hi" message using the Sonnet model to auto-start a fresh
    /// Sonnet quota window. Throttled to at most once per hour and guarded
    /// against concurrent execution. Called at login, on reset detection, and
    /// on app startup — the throttle ensures only one of those actually fires.
    func pingSonnet() async {
        guard !isSonnetPingInFlight else {
            NSLog("[AutoSession] Sonnet ping already in flight, skipping")
            return
        }

        if let last = UserDefaults.standard.object(forKey: lastSonnetPingKey) as? Date {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < sonnetPingMinInterval {
                NSLog("[AutoSession] Sonnet ping throttled (%.0fs since last)", elapsed)
                return
            }
        }

        isSonnetPingInFlight = true
        let success = await ping(model: "claude-sonnet-4-5-20250929", label: "Sonnet")
        isSonnetPingInFlight = false

        if success {
            UserDefaults.standard.set(Date(), forKey: lastSonnetPingKey)
        }
    }

    // MARK: - Ping

    @discardableResult
    private func ping(model: String, label: String) async -> Bool {
        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else {
            NSLog("[AutoSession] No credentials, skipping %@ ping", label)
            return false
        }

        NSLog("[AutoSession] %@ ping starting", label)
        var convId: String?
        var success = false
        do {
            convId = try await createConversation(sessionKey: sessionKey, orgId: orgId)
            guard let id = convId else { throw AutoSessionError.createFailed }
            try await sendMessage(sessionKey: sessionKey, orgId: orgId, convId: id, model: model)
            success = true
            NSLog("[AutoSession] %@ ping successful", label)
        } catch {
            NSLog("[AutoSession] %@ ping FAILED: %@", label, String(describing: error))
        }

        if let convId {
            try? await deleteConversation(sessionKey: sessionKey, orgId: orgId, convId: convId)
        }

        await onPingCompleted?()
        return success
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...201).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let respBody = String(data: data, encoding: .utf8) ?? "nil"
            NSLog("[AutoSession] Create conversation FAILED: %d — %@", code, respBody)
            throw AutoSessionError.createFailed
        }

        return convUUID
    }

    private func sendMessage(sessionKey: String, orgId: String, convId: String, model: String) async throws {
        let urlString = APIConstants.baseURL + APIConstants.completionPath(orgId: orgId, convId: convId)
        guard let url = URL(string: urlString) else { throw AutoSessionError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "prompt": "hi",
            "timezone": TimeZone.current.identifier,
            "model": model
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let respBody = String(data: data, encoding: .utf8) ?? "nil"
            NSLog("[AutoSession] Send message FAILED: %d — %@", code, respBody)
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
