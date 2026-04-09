import SwiftUI

@Observable @MainActor
final class MenuBarViewModel {
    let appState: AppState
    let notesManager: NotesManager
    let statusService: StatusService
    private(set) var clockTick: Date = .now
    private var clockTimer: Timer?

    var appLocale: Locale {
        if let lang = notesManager.settings.language {
            return Locale(identifier: lang)
        }
        return .current
    }

    init(appState: AppState, notesManager: NotesManager, statusService: StatusService) {
        self.appState = appState
        self.notesManager = notesManager
        self.statusService = statusService
    }

    // MARK: - Status

    private var statusDotColor: Color {
        switch appState.claudeSystemStatus {
        case .operational: .green
        case .degraded, .major, .maintenance: .red
        }
    }

    var connectionDotColor: Color {
        switch appState.connectionStatus {
        case .connected: statusDotColor
        case .disconnected: .gray
        case .error: statusDotColor // reflect system status, not connection error
        }
    }

    var statusTooltip: String {
        if case .disconnected = appState.connectionStatus {
            return String(localized: "No internet connection", bundle: .app)
        }
        switch appState.claudeSystemStatus {
        case .operational: return String(localized: "Claude status: Stable", bundle: .app)
        case .degraded, .major, .maintenance: return String(localized: "Claude status: Outage", bundle: .app)
        }
    }

    var lastUpdateText: String {
        _ = clockTick
        if case .error(let msg) = appState.connectionStatus {
            return msg
        }
        guard let date = appState.lastUpdateDate else { return "--" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return String(localized: "now", bundle: .app) }
        let minutes = seconds / 60
        return String(localized: "\(minutes) min ago", bundle: .app)
    }

    /// Whether the last-update area should highlight (connection error or stale data)
    var isLastUpdateWarning: Bool {
        _ = clockTick
        if case .error = appState.connectionStatus { return true }
        if let date = appState.lastUpdateDate {
            return Date().timeIntervalSince(date) / 60 > 10
        }
        return false
    }

    func openStatusPage() {
        statusService.openStatusPage()
    }

    // MARK: - Pacing

    var paceStatusColor: Color {
        switch appState.paceStatus {
        case .comfortable, .steady: DT.Colors.statusGreen
        case .moderate, .elevated: DT.Colors.statusOrange
        case .high, .critical: DT.Colors.statusRed
        case .unknown: .secondary
        }
    }

    var paceStrategy: String {
        appState.aiPacingMessage?.message ?? ""
    }

    // MARK: - Time Fractions

    var timeElapsedFraction: Double {
        _ = clockTick
        guard let resetDate = appState.sessionResetDate else { return 0 }
        let totalWindow = TimingConstants.sessionWindowDuration
        let remaining = resetDate.timeIntervalSince(Date())
        guard remaining > 0 else { return 1 }
        return 1.0 - (remaining / totalWindow)
    }

    var weeklyTimeElapsed: Double {
        _ = clockTick
        guard let resetDate = appState.weeklyResetDate else { return 0 }
        let totalWindow = TimingConstants.weeklyWindowDuration
        let remaining = resetDate.timeIntervalSince(Date())
        guard remaining > 0 else { return 1 }
        return 1.0 - (remaining / totalWindow)
    }

    // MARK: - Prediction

    var predictedDepletionDate: Date? {
        _ = clockTick
        guard let resetDate = appState.sessionResetDate, resetDate > Date() else { return nil }
        let usage = appState.sessionUsage
        guard usage > 0.05, usage < 1.0 else { return nil }

        let totalWindow = TimingConstants.sessionWindowDuration
        let remaining = resetDate.timeIntervalSince(Date())
        let elapsed = totalWindow - remaining
        guard elapsed > 60 else { return nil }

        let rate = usage / elapsed
        guard rate > 0 else { return nil }

        let secondsToFull = (1.0 - usage) / rate
        return Date().addingTimeInterval(secondsToFull)
    }

    var isDepletionWithinSession: Bool {
        guard let depletion = predictedDepletionDate,
              let reset = appState.sessionResetDate else { return false }
        return depletion < reset
    }

    // MARK: - Weekly Smart Color

    var weeklySmartColor: Color {
        _ = clockTick
        let usage = appState.weeklyUsage
        guard let resetDate = appState.weeklyResetDate, resetDate > Date() else {
            return DT.Colors.weeklyBlue
        }
        let totalWindow = TimingConstants.weeklyWindowDuration
        let remaining = resetDate.timeIntervalSince(Date())
        let elapsed = totalWindow - remaining
        let elapsedFraction = max(0.01, elapsed / totalWindow)
        let remainingDays = remaining / 86400

        if usage > 0.85 && remainingDays < 1.5 { return DT.Colors.statusRed }
        if usage > 0.70 && remainingDays < 0.5 { return DT.Colors.statusRed }
        if usage < 0.20 { return DT.Colors.statusGreen }

        let ratio = usage / elapsedFraction
        if ratio > 1.5 && usage > 0.50 { return DT.Colors.statusOrange }
        if ratio < 0.9 { return DT.Colors.statusGreen }

        return DT.Colors.weeklyBlue
    }

    // MARK: - Gauge (Usage Rate)

    var sessionRate: Double {
        _ = clockTick
        let elapsed = timeElapsedFraction
        guard elapsed > 0.01 else { return 0 }
        return appState.sessionUsage / elapsed
    }

    var weeklyRate: Double {
        _ = clockTick
        let elapsed = weeklyTimeElapsed
        guard elapsed > 0.01 else { return 0 }
        let effectiveUsage = max(0, appState.weeklyUsage - appState.weeklyResetBaselineUsage)
        return effectiveUsage / elapsed
    }

    var sessionRateBadgeText: String { rateBadgeText(for: sessionRate) }
    var sessionRateBadgeColor: Color { rateBadgeColor(for: sessionRate) }
    var weeklyRateBadgeText: String { weeklyBadgeText(for: weeklyRate) }
    var weeklyRateBadgeColor: Color { weeklyBadgeColor(for: weeklyRate) }
    var sessionDeviationText: String { deviationText(for: sessionRate) }
    var weeklyDeviationText: String { deviationText(for: weeklyRate) }

    private func deviationText(for rate: Double) -> String {
        let pct = Int((rate - 1.0) * 100)
        if pct <= 3 { return String(localized: "No deviation", bundle: .app) }
        return String(localized: "+\(pct)% deviation", bundle: .app)
    }

    private func rateBadgeText(for rate: Double) -> String {
        switch rate {
        case ..<0.5: String(localized: "Low usage", bundle: .app)
        case 0.5..<0.9: String(localized: "Ideal", bundle: .app)
        case 0.9..<1.2: String(localized: "On track", bundle: .app)
        case 1.2..<1.7: String(localized: "Limit risk", bundle: .app)
        default: String(localized: "Limit reached", bundle: .app)
        }
    }

    private func rateBadgeColor(for rate: Double) -> Color {
        switch rate {
        case ..<0.5: Color(red: 0.13, green: 0.78, blue: 0.34)
        case 0.5..<0.9: Color(red: 0.13, green: 0.78, blue: 0.34)
        case 0.9..<1.2: Color(red: 0.97, green: 0.75, blue: 0.08)
        case 1.2..<1.7: Color(red: 1.00, green: 0.35, blue: 0.05)
        default: Color(red: 0.90, green: 0.08, blue: 0.05)
        }
    }

    private func weeklyBadgeText(for rate: Double) -> String {
        switch rate {
        case ..<0.5: String(localized: "Low usage", bundle: .app)
        case 0.5..<0.9: String(localized: "Ideal", bundle: .app)
        case 0.9..<1.2: String(localized: "On track", bundle: .app)
        case 1.2..<1.7: String(localized: "Limit risk", bundle: .app)
        default: String(localized: "Limit reached", bundle: .app)
        }
    }

    private func weeklyBadgeColor(for rate: Double) -> Color {
        rateBadgeColor(for: rate)
    }

    // MARK: - Donut Cards

    var sessionRenewalText: String {
        _ = clockTick
        guard let date = appState.sessionResetDate, date > Date() else { return "" }
        return formatRemainingTime(date)
    }

    var weeklyRenewalText: String {
        _ = clockTick
        guard let date = appState.weeklyResetDate, date > Date() else { return "" }
        return formatRemainingTime(date)
    }

    // MARK: - Sonnet Bar

    var sonnetBarProgress: Double { appState.sonnetUsage }

    var sonnetResetText: String {
        _ = clockTick
        guard let date = appState.sonnetResetDate, date > Date() else { return "" }
        return formatRemaining(date, suffix: String(localized: "remaining", bundle: .app))
    }

    // MARK: - Session Gauge Badge (show differently when quota is full)

    var sessionGaugeBadgeText: String {
        if appState.sessionUsage >= 1.0 { return String(localized: "Limit Reached", bundle: .app) }
        if isDepletionWithinSession { return String(localized: "Burning too fast", bundle: .app) }
        return sessionRateBadgeText
    }

    var sessionGaugeBadgeColor: Color {
        if appState.sessionUsage >= 1.0 { return DT.Colors.statusRed }
        if isDepletionWithinSession { return DT.Colors.statusRed }
        return sessionRateBadgeColor
    }

    // MARK: - Extra Usage

    var extraUsageVisible: Bool {
        guard let extra = appState.extraUsage, extra.isEnabled else { return false }
        // Always show if unlimited, only show if spending if limited
        if extra.monthlyLimit == nil { return true }
        return (extra.usedCredits ?? 0) > 0
    }

    var isExtraUnlimited: Bool {
        guard let extra = appState.extraUsage, extra.isEnabled else { return false }
        return extra.monthlyLimit == nil
    }

    var extraUsageProgress: Double {
        guard let util = appState.extraUsage?.utilization else { return 0 }
        return min(1, util / 100.0)
    }

    var extraCurrentBalanceText: String? {
        guard let balance = appState.extraUsage?.currentBalance else { return nil }
        return String(format: "$%.2f", balance / 100.0)
    }

    var extraAutoReload: Bool? {
        appState.extraUsage?.autoReload
    }

    var extraResetText: String {
        _ = clockTick
        guard extraUsageVisible else { return "" }
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        guard let nextMonth = calendar.date(from: comps) else { return "" }
        return formatRemaining(nextMonth, suffix: String(localized: "remaining", bundle: .app))
    }

    var extraUsageValueText: String {
        guard let extra = appState.extraUsage else { return "" }
        let used = (extra.usedCredits ?? 0) / 100.0
        if let limit = extra.monthlyLimit {
            let limitDollars = limit / 100.0
            return String(format: "$%.2f / $%.2f", used, limitDollars)
        }
        return String(format: "$%.2f", used)
    }

    // MARK: - Chart X Labels

    var sessionHourLabels: [String] {
        guard let resetDate = appState.sessionResetDate else { return [] }
        let startDate = resetDate.addingTimeInterval(-TimingConstants.sessionWindowDuration)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return (0...5).map { i in
            formatter.string(from: startDate.addingTimeInterval(Double(i) * 3600))
        }
    }

    var weeklyDayLabels: [String] {
        guard let resetDate = appState.weeklyResetDate else { return [] }
        let startDate = resetDate.addingTimeInterval(-TimingConstants.weeklyWindowDuration)
        let dayFmt = DateFormatter()
        dayFmt.locale = appLocale
        dayFmt.dateFormat = "d MMM"
        let startLabel = dayFmt.string(from: startDate)
        let endLabel = dayFmt.string(from: resetDate)
        let midFmt = DateFormatter()
        midFmt.locale = appLocale
        midFmt.dateFormat = "EEE"
        var labels = [startLabel]
        for i in 1..<7 {
            labels.append(midFmt.string(from: startDate.addingTimeInterval(Double(i) * 86400)).capitalized)
        }
        labels.append(endLabel)
        return labels
    }

    // MARK: - Two-line Time (day/hour stacked next to icon)

    var sonnetResetLines: (String, String) {
        _ = clockTick
        guard let date = appState.sonnetResetDate, date > Date() else { return ("", "") }
        return formatRemainingLines(date)
    }

    var extraResetLines: (String, String) {
        _ = clockTick
        guard extraUsageVisible else { return ("", "") }
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        guard let nextMonth = calendar.date(from: comps) else { return ("", "") }
        return formatRemainingLines(nextMonth)
    }

    var extraMonthlyLimitText: String? {
        guard let limit = appState.extraUsage?.monthlyLimit else { return nil }
        return String(format: "/ $%.0f", limit / 100.0)
    }

    var extraUsedText: String {
        guard let extra = appState.extraUsage else { return "" }
        return String(format: "$%.2f", max(0, extra.usedCredits ?? 0) / 100.0)
    }

    private func formatRemainingLines(_ date: Date) -> (String, String) {
        let remaining = date.timeIntervalSince(Date())
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        let dUnit = String(localized: "d", bundle: .app)
        let hUnit = String(localized: "h", bundle: .app)
        let mUnit = String(localized: "m", bundle: .app)

        if days >= 1 {
            return ("\(days)\(dUnit)", "\(hours)\(hUnit)")
        }
        if hours >= 1 {
            return ("\(hours)\(hUnit)", "\(minutes)\(mUnit)")
        }
        return ("\(max(1, minutes))\(mUnit)", "")
    }

    // MARK: - Shared Formatter

    private func formatRemainingTime(_ date: Date) -> String {
        let remaining = date.timeIntervalSince(Date())
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        let dUnit = String(localized: "d", bundle: .app)
        let hUnit = String(localized: "h", bundle: .app)
        let mUnit = String(localized: "m", bundle: .app)

        if days >= 1 {
            return "\(days)\(dUnit) \(hours)\(hUnit)"
        }
        if hours >= 1 {
            return "\(hours)\(hUnit) \(minutes)\(mUnit)"
        }
        return "\(max(1, minutes))\(mUnit)"
    }

    private func formatRemaining(_ date: Date, suffix: String) -> String {
        let remaining = date.timeIntervalSince(Date())
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        let dUnit = String(localized: "d", bundle: .app)
        let hUnit = String(localized: "h", bundle: .app)
        let mUnit = String(localized: "m", bundle: .app)

        if days >= 1 {
            return "\(days)\(dUnit) \(hours)\(hUnit) \(suffix)"
        }
        if hours >= 1 {
            return "\(hours)\(hUnit) \(minutes)\(mUnit) \(suffix)"
        }
        return "\(max(1, minutes))\(mUnit) \(suffix)"
    }

    // MARK: - Account Details

    var accountPlanDisplayName: String {
        if let tier = appState.rateLimitTier?.lowercased() {
            if tier.contains("max_20") || tier.contains("max20") { return "Max 20" }
            if tier.contains("max_5") || tier.contains("max5") { return "Max 5" }
            if tier.contains("enterprise") { return "Enterprise" }
            if tier.contains("team") { return "Team" }
            if tier.contains("pro") { return "Pro" }
            if tier.contains("free") { return "Free" }
        }
        return appState.planName ?? "Unknown"
    }

    var accountBillingDisplayText: String? {
        guard let billing = appState.billingType else { return nil }
        switch billing {
        case "stripe_subscription":
            return String(localized: "Active Subscription", bundle: .app)
        default:
            return billing.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var accountMemberSinceText: String? {
        guard let date = appState.memberSince else { return nil }
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var accountExtraUsageStatusText: String {
        guard let extra = appState.extraUsage else {
            return String(localized: "Not Available", bundle: .app)
        }
        return extra.isEnabled
            ? String(localized: "Enabled", bundle: .app)
            : String(localized: "Disabled", bundle: .app)
    }

    var accountSpendingText: String? {
        guard let extra = appState.extraUsage, extra.isEnabled else { return nil }
        let used = (extra.usedCredits ?? 0) / 100.0
        guard used > 0 else { return nil }
        return String(format: "$%.2f", used)
    }

    var accountSpendingCapText: String? {
        guard let extra = appState.extraUsage, extra.isEnabled else { return nil }
        guard let limit = extra.monthlyLimit else {
            return String(localized: "Unlimited", bundle: .app)
        }
        return String(format: "$%.0f", limit / 100.0)
    }

    var accountDataRetentionText: String? {
        guard let retention = appState.dataRetention else { return nil }
        switch retention {
        case "default":
            return String(localized: "Standard", bundle: .app)
        case "none", "disabled":
            return String(localized: "Disabled", bundle: .app)
        case "custom":
            return String(localized: "Custom", bundle: .app)
        default:
            return retention.capitalized
        }
    }

    // MARK: - Clock

    func startClockTick() {
        guard clockTimer == nil else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clockTick = .now
            }
        }
    }

    func stopClockTick() {
        clockTimer?.invalidate()
        clockTimer = nil
    }
}
