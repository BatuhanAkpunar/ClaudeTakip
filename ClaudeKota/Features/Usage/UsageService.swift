import Foundation
import Network

@MainActor
final class UsageService {
    private let appState: AppState
    private let authManager: AuthManager
    private var pollingTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    init(appState: AppState, authManager: AuthManager) {
        self.appState = appState
        self.authManager = authManager
        setupNetworkMonitor()
    }

    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: TimingConstants.usagePollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsageIfNeeded()
            }
        }
        Task { await fetchUsage() }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func manualRefresh() async {
        guard canManualRefresh() else { return }
        appState.manualRefreshCount += 1
        if appState.manualRefreshCount >= TimingConstants.maxManualRefreshes {
            appState.refreshCooldownEnd = Date().addingTimeInterval(TimingConstants.manualRefreshCooldown)
        }
        await fetchUsage()
    }

    func fetchUsage() async {
        guard isNetworkAvailable else { return }
        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else { return }

        let urlString = APIConstants.baseURL + APIConstants.usagePath(orgId: orgId)
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                authManager.signOut()
                return
            }

            guard httpResponse.statusCode == 200 else {
                handleError()
                return
            }

            let usage = try UsageResponseParser.parse(data)
            appState.previousUsage = appState.sessionUsage
            appState.sessionUsage = usage.fiveHour
            appState.sessionRemaining = usage.sessionRemaining
            appState.weeklyUsage = usage.sevenDay
            appState.lastUpdateDate = Date()
            appState.connectionStatus = .connected
            appState.consecutiveErrors = 0

            updateResetDates(usage: usage)
        } catch is UsageParseError {
            appState.connectionStatus = .error("Veri okunamiyor")
        } catch {
            handleError()
        }
    }

    // MARK: - Private

    private func fetchUsageIfNeeded() async {
        guard isNetworkAvailable else { return }
        // 3+ ardisik hata sonrasi ek 30s bekleme
        if appState.consecutiveErrors >= 3 {
            try? await Task.sleep(for: .seconds(TimingConstants.retryDelay))
        }
        await fetchUsage()
    }

    private func canManualRefresh() -> Bool {
        if let cooldownEnd = appState.refreshCooldownEnd {
            if Date() > cooldownEnd {
                appState.manualRefreshCount = 0
                appState.refreshCooldownEnd = nil
                return true
            }
            return false
        }
        return appState.manualRefreshCount < TimingConstants.maxManualRefreshes
    }

    private func handleError() {
        appState.consecutiveErrors += 1
        if appState.consecutiveErrors >= TimingConstants.maxConsecutiveErrors {
            appState.connectionStatus = .error("Baglanti sorunu")
        }
    }

    private func updateResetDates(usage: UsageData) {
        if let previousUsage = appState.previousUsage,
           previousUsage == 0, usage.fiveHour > 0 {
            appState.sessionResetDate = Date().addingTimeInterval(TimingConstants.sessionWindowDuration)
        }
        if let previousUsage = appState.previousUsage,
           usage.fiveHour < previousUsage - 0.05 {
            appState.sessionResetDate = nil
            appState.previousUsage = nil
        }
    }

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                if !wasAvailable && self.isNetworkAvailable {
                    await self.fetchUsage()
                }
                if !self.isNetworkAvailable {
                    self.appState.connectionStatus = .disconnected
                }
            }
        }
        networkMonitor.start(queue: .global(qos: .utility))
    }
}
