import Foundation

@MainActor
final class PacingMessageService {
    private let appState: AppState
    private let notesManager: NotesManager
    private var debounceTask: Task<Void, Never>?
    private var inFlightTask: Task<Void, Never>?
    private var lastFetchedState: PaceStatus?
    private var lastFetchedAt: Date?
    private var lastFetchedLanguage: String?
    private var consecutiveErrors: Int = 0

    init(appState: AppState, notesManager: NotesManager) {
        self.appState = appState
        self.notesManager = notesManager
    }

    private var currentLanguage: String {
        notesManager.settings.language ?? Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Whether Groq calls are blocked due to repeated failures.
    var isBlocked: Bool {
        consecutiveErrors >= GroqConstants.maxConsecutiveErrors
    }

    // MARK: - Triggers

    func onAppLaunch() {
        guard appState.hasLoadedUsage,
              appState.paceStatus != .unknown,
              !isUsageEmpty
        else { return }
        consecutiveErrors = 0
        appState.isAIUnavailable = false
        fetchNow(reason: "launch")
    }

    func onStateChanged(to newState: PaceStatus) {
        guard newState != .unknown, !isUsageEmpty else { return }

        let languageChanged = currentLanguage != lastFetchedLanguage

        if !languageChanged,
           newState == lastFetchedState,
           let fetchedAt = lastFetchedAt,
           Date().timeIntervalSince(fetchedAt) < GroqConstants.staleCacheInterval {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GroqConstants.debounceInterval))
            guard !Task.isCancelled else { return }
            self?.fetchNow(reason: "stateChange")
        }
    }

    func onPopoverOpen() {
        guard appState.paceStatus != .unknown, !isUsageEmpty else { return }
        if let fetchedAt = lastFetchedAt,
           Date().timeIntervalSince(fetchedAt) < GroqConstants.debounceInterval {
            return
        }
        fetchNow(reason: "popoverOpen")
    }

    func onStaleCacheCheck() {
        guard appState.paceStatus != .unknown, !isUsageEmpty else { return }

        // Language change: invalidate cache and refetch immediately
        if lastFetchedLanguage != nil, currentLanguage != lastFetchedLanguage {
            appState.aiPacingMessage = nil
            debounceTask?.cancel()
            fetchNow(reason: "languageChanged")
            return
        }

        guard let fetchedAt = lastFetchedAt,
              Date().timeIntervalSince(fetchedAt) >= GroqConstants.staleCacheInterval
        else { return }

        fetchNow(reason: "stale")
    }

    /// No meaningful usage data yet — skip Groq.
    private var isUsageEmpty: Bool {
        appState.sessionUsage <= 0 && appState.weeklyUsage <= 0
    }

    // MARK: - Initial Fetch

    func fetchInitialMessage(timeout: TimeInterval = 8) async {
        guard notesManager.settings.aiRecommendation, !isUsageEmpty else { return }

        inFlightTask?.cancel()
        appState.isFetchingAIMessage = true
        let context = buildContext()
        let language = currentLanguage

        let fetchTask = Task { @MainActor in
            try await GroqClient.fetchMessage(context: context, language: language)
        }
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            fetchTask.cancel()
        }

        do {
            let message = try await fetchTask.value
            timeoutTask.cancel()
            appState.aiPacingMessage = message
            lastFetchedState = appState.paceStatus
            lastFetchedAt = Date()
            lastFetchedLanguage = language
            consecutiveErrors = 0
        } catch {
            timeoutTask.cancel()
        }
        appState.isFetchingAIMessage = false
    }

    // MARK: - Fetch

    private func fetchNow(reason: String) {
        guard notesManager.settings.aiRecommendation else { return }
        guard consecutiveErrors < GroqConstants.maxConsecutiveErrors else {
            appState.isAIUnavailable = true
            return
        }

        inFlightTask?.cancel()
        inFlightTask = Task { [weak self] in
            guard let self else { return }

            appState.isFetchingAIMessage = true
            let context = buildContext()
            let language = currentLanguage

            do {
                let message = try await GroqClient.fetchMessage(context: context, language: language)

                guard !Task.isCancelled else { return }

                appState.aiPacingMessage = message
                appState.isAIUnavailable = false
                lastFetchedState = appState.paceStatus
                lastFetchedAt = Date()
                lastFetchedLanguage = language
                consecutiveErrors = 0
            } catch is CancellationError {
                return
            } catch GroqError.rateLimited {
                consecutiveErrors += 1
                if isBlocked { appState.isAIUnavailable = true }
            } catch {
                consecutiveErrors += 1
                if isBlocked { appState.isAIUnavailable = true }
            }
            appState.isFetchingAIMessage = false
        }
    }

    // MARK: - Context Building

    private func buildContext() -> String {
        let sessionPercent = Int(appState.sessionUsage * 100)
        let weeklyPercent = Int(appState.weeklyUsage * 100)
        let sonnetPercent = Int(appState.sonnetUsage * 100)

        // Session speed multiplier
        let sessionRate: Double
        if let resetDate = appState.sessionResetDate {
            let elapsed = Date().timeIntervalSince(
                resetDate.addingTimeInterval(-TimingConstants.sessionWindowDuration)
            )
            let fraction = max(0.01, elapsed / TimingConstants.sessionWindowDuration)
            sessionRate = min(10.0, appState.sessionUsage / fraction)
        } else {
            sessionRate = 1.0
        }

        // Weekly speed multiplier
        let weeklyRate: Double
        if let resetDate = appState.weeklyResetDate, resetDate > Date() {
            let totalWindow = TimingConstants.weeklyWindowDuration
            let remaining = resetDate.timeIntervalSince(Date())
            let elapsed = totalWindow - remaining
            let fraction = max(0.01, elapsed / totalWindow)
            weeklyRate = min(10.0, appState.weeklyUsage / fraction)
        } else {
            weeklyRate = 1.0
        }

        // Extra usage analysis
        let extraUsed = appState.extraUsage?.isEnabled == true
            && (appState.extraUsage?.usedCredits ?? 0) > 0
        let extraLimitCritical: Bool = {
            guard let extra = appState.extraUsage, extra.isEnabled,
                  let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0
            else { return false }
            return (used / limit) > 0.80
        }()

        // Calculate tone
        let tone = calculateTone(
            sessionPercent: sessionPercent,
            weeklyPercent: weeklyPercent,
            sessionRate: sessionRate,
            weeklyRate: weeklyRate,
            extraUsed: extraUsed,
            extraLimitCritical: extraLimitCritical
        )

        // Build compact context
        var parts: [String] = []

        parts.append("Session: \(sessionPercent)%, renewal: \(formatSessionReset())")
        parts.append("Weekly: \(weeklyPercent)%, renewal: \(formatWeeklyReset())")
        parts.append("Speed: session \(String(format: "%.1f", sessionRate))x, weekly \(String(format: "%.1f", weeklyRate))x")

        // Only include Sonnet if high
        if sonnetPercent > 60 {
            parts.append("Sonnet: %\(sonnetPercent)")
        }

        // Extra usage info — send to model based on context
        let quotasHigh = sessionPercent > 70 || weeklyPercent > 70
        let quotasFull = sessionPercent >= 100 || weeklyPercent >= 100

        if let extra = appState.extraUsage {
            if !extra.isEnabled {
                // Extra disabled — inform model if quota is full (so it can suggest enabling)
                if quotasFull {
                    parts.append("Extra: disabled")
                }
            } else if extra.monthlyLimit == nil {
                // Unlimited mode
                let spent = (extra.usedCredits ?? 0)
                if spent > 0 {
                    parts.append("Extra: unlimited, \(String(format: "$%.2f", spent / 100.0)) spent")
                } else if quotasHigh {
                    parts.append("Extra: unlimited, not yet used")
                }
            } else {
                // Capped mode
                let spent = (extra.usedCredits ?? 0)
                let limit = (extra.monthlyLimit ?? 0)
                let capPercent = limit > 0 ? Int(spent / limit * 100) : 0
                if spent > 0 {
                    let tag = extraLimitCritical ? " (cap almost reached)" : ""
                    parts.append("Extra: has spending cap, \(capPercent)% of cap used\(tag)")
                } else if quotasHigh {
                    parts.append("Extra: has spending cap, unused")
                }
            }
        }

        // If quota was depleted earlier today (only in risky zone)
        if let overflowDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastSessionOverflowDate) as? Date,
           Calendar.current.isDateInToday(overflowDate),
           appState.sessionUsage < 1.0,
           appState.sessionUsage >= 0.5 {
            parts.append("Note: Session quota was depleted earlier today")
        }

        // Visual indicator color (so AI can align its message)
        let visual: String
        switch appState.paceStatus {
        case .comfortable, .steady: visual = "green"
        case .moderate, .elevated: visual = "orange"
        case .high, .critical: visual = "red"
        case .unknown: visual = "neutral"
        }
        parts.append("Visual: \(visual)")
        parts.append("Tone: \(tone)")

        return parts.joined(separator: " | ")
    }

    // MARK: - Tone Calculation

    private func calculateTone(
        sessionPercent: Int,
        weeklyPercent: Int,
        sessionRate: Double,
        weeklyRate: Double,
        extraUsed: Bool,
        extraLimitCritical: Bool
    ) -> String {
        // Critical overrides — always urgent regardless of visual
        if sessionPercent >= 100 && weeklyPercent >= 100 { return "urgent" }
        if weeklyPercent >= 100 { return "urgent" }
        if sessionPercent >= 100 && extraUsed { return "urgent" }

        // High severity overrides
        if extraLimitCritical { return "warning" }
        if sessionPercent >= 100 { return "warning" }

        // Derive from paceStatus so tone always matches box color
        switch appState.paceStatus {
        case .high, .critical:
            return "urgent"
        case .moderate, .elevated:
            return "warning"
        case .comfortable, .steady:
            // Don't say "relaxed" if weekly acceleration is notable
            if weeklyRate > 1.8 && weeklyPercent > 25 { return "info" }
            if sessionPercent < 50 && weeklyPercent < 50 { return "relaxed" }
            return "info"
        case .unknown:
            return "info"
        }
    }

    // MARK: - Reset Time Formatters

    private func formatSessionReset() -> String {
        guard let resetDate = appState.sessionResetDate, resetDate > Date() else {
            return "unknown"
        }
        let minutes = Int(resetDate.timeIntervalSince(Date()) / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func formatWeeklyReset() -> String {
        guard let resetDate = appState.weeklyResetDate, resetDate > Date() else {
            return "unknown"
        }
        let remaining = resetDate.timeIntervalSince(Date())
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600

        if days >= 1 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h"
    }

    // MARK: - Reset

    func reset() {
        debounceTask?.cancel()
        inFlightTask?.cancel()
        lastFetchedState = nil
        lastFetchedAt = nil
        lastFetchedLanguage = nil
        consecutiveErrors = 0
        appState.isAIUnavailable = false
    }
}
