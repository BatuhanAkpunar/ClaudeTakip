import Foundation
import Network

@MainActor
final class UsageService {
    private let appState: AppState
    private let authManager: AuthManager
    private let cacheStore: UsageCacheStore
    private var pollingTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    var onSessionExpired: (() -> Void)?

    init(appState: AppState, authManager: AuthManager, cacheStore: UsageCacheStore) {
        self.appState = appState
        self.authManager = authManager
        self.cacheStore = cacheStore
        setupNetworkMonitor()
    }

    func startPolling() {
        loadCachedData()
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: TimingConstants.usagePollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsageIfNeeded()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func shutdown() {
        cacheStore.forceFlush()
        stopPolling()
        networkMonitor.cancel()
    }

    func manualRefresh() async {
        guard canManualRefresh() else { return }
        appState.manualRefreshCount += 1
        if appState.manualRefreshCount >= TimingConstants.maxManualRefreshes {
            appState.refreshCooldownEnd = Date().addingTimeInterval(TimingConstants.manualRefreshCooldown)
        }
        await fetchUsage()
    }

    /// Fetch organizations data and update account details in AppState
    func fetchAccountDetails() async {
        guard let sessionKey = authManager.getSessionKey() else { return }
        let urlString = APIConstants.baseURL + APIConstants.organizationsPath
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let org = json.first else { return }

        let billingType = org["billing_type"] as? String
        let rateLimitTier = org["rate_limit_tier"] as? String
        let capabilities = org["capabilities"] as? [String] ?? []
        let freeCreditsStatus = org["free_credits_status"] as? String

        var createdAt: Date?
        if let dateStr = org["created_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = formatter.date(from: dateStr)
        }

        appState.billingType = billingType
        appState.rateLimitTier = rateLimitTier
        appState.capabilities = capabilities
        appState.memberSince = createdAt
        appState.freeCreditsStatus = freeCreditsStatus
        appState.dataRetention = org["data_retention"] as? String

        // Fetch account profile (email, display name)
        await fetchAccountProfile(sessionKey: sessionKey)

        // Persist to keychain for offline restore
        authManager.persistAccountDetails(AccountDetails(
            billingType: billingType,
            rateLimitTier: rateLimitTier,
            capabilities: capabilities,
            createdAt: createdAt,
            freeCreditsStatus: freeCreditsStatus,
            email: appState.accountEmail,
            displayName: appState.accountDisplayName
        ))
    }

    /// Fetch /api/account for email and display name
    private func fetchAccountProfile(sessionKey: String) async {
        let urlString = APIConstants.baseURL + APIConstants.accountPath
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        appState.accountEmail = json["email_address"] as? String
        appState.accountDisplayName = json["display_name"] as? String ?? json["full_name"] as? String
    }

    func fetchUsage() async {
        guard isNetworkAvailable else { return }
        guard let sessionKey = authManager.getSessionKey(),
              let orgId = appState.organizationId else { return }

        let urlString = APIConstants.baseURL + APIConstants.usagePath(orgId: orgId)
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                onSessionExpired?()
                return
            }

            guard httpResponse.statusCode == 200 else {
                handleError()
                return
            }

            let usage = try UsageResponseParser.parse(data)
            applyUsageToState(usage)
            recordSnapshots(usage)
            cacheStore.updateCurrent(usage.toCachedUsage())

        } catch is UsageParseError {
            appState.connectionStatus = .error(String(localized: "Cannot read data", bundle: .app))
        } catch {
            handleError()
        }
    }

    // MARK: - Apply to State

    private func applyUsageToState(_ usage: UsageData) {
        // If previousUsage is nil, this is the first API response (previous came from cache).
        // The difference between cache and API values is not a real poll interval,
        // so set previousUsage to the new value — prevent false rate spikes.
        if appState.previousUsage != nil {
            appState.previousUsage = appState.sessionUsage
        } else {
            appState.previousUsage = usage.fiveHourUtilization
        }
        appState.sessionUsage = usage.fiveHourUtilization
        appState.sessionRemaining = usage.sessionRemaining

        // Track previous weekly usage for reset detection (mirrors session previousUsage)
        if appState.previousWeeklyUsage != nil {
            appState.previousWeeklyUsage = appState.weeklyUsage
        } else {
            appState.previousWeeklyUsage = usage.sevenDayUtilization
        }
        appState.weeklyUsage = usage.sevenDayUtilization

        // If session quota is full, save the date (to inform Groq in the next session)
        if usage.fiveHourUtilization >= 1.0 {
            UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastSessionOverflowDate)
        }

        // Reset date tracking — session
        if let resetDate = usage.fiveHourResetsAt {
            let oldReset = appState.sessionResetDate
            appState.sessionResetDate = resetDate
            if let old = oldReset, abs(old.timeIntervalSince(resetDate)) > 10 {
                cacheStore.clearSessionHistory()
                appState.usageHistory.removeAll()
            }
        }

        // Reset date tracking — weekly
        if let weeklyReset = usage.sevenDayResetsAt {
            let oldReset = appState.weeklyResetDate
            appState.weeklyResetDate = weeklyReset
            if let old = oldReset, abs(old.timeIntervalSince(weeklyReset)) > 10 {
                cacheStore.clearWeeklyHistory()
                appState.weeklyUsageHistory.removeAll()
            }
        }

        // Sonnet
        if let sonnetUtil = usage.sonnetUtilization {
            appState.sonnetUsage = sonnetUtil
            appState.sonnetRemaining = max(0, 1.0 - sonnetUtil)
        }
        if let sonnetReset = usage.sonnetResetsAt {
            let oldReset = appState.sonnetResetDate
            appState.sonnetResetDate = sonnetReset
            if let old = oldReset, abs(old.timeIntervalSince(sonnetReset)) > 10 {
                cacheStore.clearSonnetHistory()
                appState.sonnetUsageHistory.removeAll()
            }
        }

        // Extra usage
        appState.extraUsage = usage.extraUsage

        appState.lastUpdateDate = Date()
        appState.connectionStatus = .connected
        appState.consecutiveErrors = 0
    }

    // MARK: - Snapshots

    private func recordSnapshots(_ usage: UsageData) {
        // Session
        cacheStore.recordSessionSnapshot(usage: usage.fiveHourUtilization)
        appState.usageHistory = cacheStore.cache.sessionHistory

        // Weekly — record every 10 min
        let lastWeeklyTime = cacheStore.cache.weeklyHistory.last?.timestamp ?? .distantPast
        if Date().timeIntervalSince(lastWeeklyTime) >= 600 {
            cacheStore.recordWeeklySnapshot(usage: usage.sevenDayUtilization)
        }
        appState.weeklyUsageHistory = cacheStore.cache.weeklyHistory

        // Sonnet
        if let sonnet = usage.sonnetUtilization {
            cacheStore.recordSonnetSnapshot(usage: sonnet)
            appState.sonnetUsageHistory = cacheStore.cache.sonnetHistory
        }

    }

    // MARK: - Load Cached Data

    private func loadCachedData() {
        cacheStore.load()
        let c = cacheStore.cache

        // Only load histories — needed for charts
        // Current values and hasLoadedUsage are not loaded,
        // UI shows LoadingView until fresh API data arrives
        appState.usageHistory = c.sessionHistory
        appState.weeklyUsageHistory = c.weeklyHistory
        appState.sonnetUsageHistory = c.sonnetHistory
    }

    // MARK: - Private

    private func fetchUsageIfNeeded() async {
        guard isNetworkAvailable else { return }
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
            appState.connectionStatus = .error(String(localized: "Connection problem", bundle: .app))
        }
    }

    // MARK: - Network

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
