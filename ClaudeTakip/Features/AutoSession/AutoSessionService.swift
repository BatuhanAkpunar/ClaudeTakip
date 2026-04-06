import Foundation
import os.log

private let logger = Logger(subsystem: "com.batuhanakpunar.ClaudeTakip", category: "AutoSession")

@MainActor
final class AutoSessionService {
    private let appState: AppState
    private let authManager: AuthManager
    private let notesManager: NotesManager
    private var scheduledTask: Task<Void, Never>?
    private var scheduledResetDate: Date?

    init(appState: AppState, authManager: AuthManager, notesManager: NotesManager) {
        self.appState = appState
        self.authManager = authManager
        self.notesManager = notesManager
    }

    // MARK: - Schedule

    /// Call whenever `sessionResetDate` changes (from UsageService, pacing loop, etc.)
    func scheduleIfNeeded() {
        guard notesManager.settings.autoSession else { return }

        guard let resetDate = appState.sessionResetDate, resetDate > Date() else {
            // No future reset date — check if session is already expired
            if appState.hasLoadedUsage, appState.sessionResetDate == nil || (appState.sessionResetDate ?? .distantFuture) < Date() {
                // Session expired or no active session — try to start now
                scheduleStart(after: 5)
            }
            return
        }

        // Already scheduled for this exact reset date
        if scheduledResetDate == resetDate { return }

        // Schedule for when the session expires + small buffer
        let delay = resetDate.timeIntervalSince(Date()) + 5
        logger.debug("[AutoSession] Scheduled for \(Int(delay))s from now (reset at \(resetDate.description))")
        scheduleStart(after: delay)
        scheduledResetDate = resetDate
    }

    func stopMonitoring() {
        scheduledTask?.cancel()
        scheduledTask = nil
        scheduledResetDate = nil
    }

    func resetState() {
        stopMonitoring()
    }

    // MARK: - On Launch

    func checkOnLaunch() async {
        guard notesManager.settings.autoSession,
              appState.hasLoadedUsage else { return }

        // If session is already expired at launch, start immediately
        if let resetDate = appState.sessionResetDate, resetDate < Date() {
            logger.debug("[AutoSession] Launch: session already expired, starting...")
            await startSession()
        } else if appState.sessionResetDate == nil {
            logger.debug("[AutoSession] Launch: no active session, starting...")
            await startSession()
        }
        // Otherwise scheduleIfNeeded() will handle it when resetDate is set
    }

    // MARK: - Manual Start (UI button)

    func startSessionNow() async {
        await startSession()
    }

    // MARK: - Private

    private func scheduleStart(after delay: TimeInterval) {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(1, delay)))
            } catch { return }

            guard let self, !Task.isCancelled else { return }
            guard notesManager.settings.autoSession else {
                logger.debug("[AutoSession] Scheduled fire: autoSession disabled, skipping")
                return
            }

            // Verify session is actually expired
            if let resetDate = appState.sessionResetDate, resetDate > Date() {
                logger.debug("[AutoSession] Scheduled fire: session still active, skipping")
                return
            }

            logger.debug("[AutoSession] Scheduled fire: starting session...")
            await startSession()
        }
    }

    private func startSession() async {
        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else {
            logger.debug("[AutoSession] No credentials, cannot start session")
            return
        }

        var convId: String?
        do {
            convId = try await createConversation(sessionKey: sessionKey, orgId: orgId)
            guard let id = convId else { throw AutoSessionError.createFailed }
            try await sendMessage(sessionKey: sessionKey, orgId: orgId, convId: id, model: "claude-3-5-haiku-20241022")
            logger.debug("[AutoSession] New session started successfully")
        } catch {
            logger.debug("[AutoSession] Failed: \(type(of: error))")
        }

        if let convId {
            try? await deleteConversation(sessionKey: sessionKey, orgId: orgId, convId: convId)
        }

        // Clear scheduled state so next resetDate change re-schedules
        scheduledResetDate = nil
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
