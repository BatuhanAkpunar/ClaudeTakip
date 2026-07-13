import Foundation

struct UsageData: Sendable {
    let fiveHourUtilization: Double   // 0-1 range (API returns 0-100, divided by 100 during parse)
    let sevenDayUtilization: Double   // 0-1 range
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?

    // Model-scoped weekly limit. The `sonnet*` names are retained to minimize
    // blast radius, but they now mean "the model-scoped weekly limit" — sourced
    // from the live `limits` array (kind == "weekly_scoped") when present, and
    // falling back to the legacy top-level `seven_day_sonnet` bucket otherwise.
    let sonnetUtilization: Double?
    let sonnetResetsAt: Date?
    /// API-provided display name for the model-scoped weekly limit (e.g. "Fable").
    /// nil when sourced from the legacy bucket.
    let modelLimitName: String?
    // Extra usage (overage billing)
    let extraUsage: ExtraUsageInfo?

    var sessionRemaining: Double { max(0, 1.0 - fiveHourUtilization) }

    /// Convert to CachedUsage (for writing to disk)
    func toCachedUsage() -> CachedUsage {
        CachedUsage(
            fiveHour: UsageBucket(utilization: fiveHourUtilization, resetsAt: fiveHourResetsAt),
            sevenDay: UsageBucket(utilization: sevenDayUtilization, resetsAt: sevenDayResetsAt),
            sevenDaySonnet: sonnetUtilization.map { UsageBucket(utilization: $0, resetsAt: sonnetResetsAt) },
            extraUsage: extraUsage,
            modelLimitName: modelLimitName
        )
    }
}

enum UsageParseError: Error, LocalizedError {
    case missingFields
    case invalidData

    var errorDescription: String? {
        switch self {
        case .missingFields: String(localized: "Usage data is missing", bundle: .app)
        case .invalidData: String(localized: "Invalid data format", bundle: .app)
        }
    }
}

enum UsageResponseParser {
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let dateFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ data: Data) throws -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParseError.missingFields
        }

        let fiveHour = parseUtilizationBucket(json["five_hour"])
        let sevenDay = parseUtilizationBucket(json["seven_day"])
        let extra = parseExtraUsage(json["extra_usage"])

        guard fiveHour.utilization != nil || sevenDay.utilization != nil else {
            throw UsageParseError.missingFields
        }

        // Model-scoped weekly limit — new API shape (limits array). Prefer the
        // live weekly_scoped entry; fall back to the legacy seven_day_sonnet
        // bucket for accounts still returning it. `utilization` is already
        // normalized to 0-100 in both branches.
        let scoped = parseWeeklyScopedLimit(json: json)
        let sonnetUtilization100: Double?
        let sonnetResetsAt: Date?
        let modelLimitName: String?
        if let scopedUtil = scoped.utilization {
            sonnetUtilization100 = scopedUtil
            sonnetResetsAt = scoped.resetsAt
            modelLimitName = scoped.modelName
        } else {
            let legacy = findModelBucket(json: json, containing: "sonnet")
            sonnetUtilization100 = legacy.utilization
            sonnetResetsAt = legacy.resetsAt
            modelLimitName = nil
        }

        return UsageData(
            fiveHourUtilization: (fiveHour.utilization ?? 0) / 100.0,
            sevenDayUtilization: (sevenDay.utilization ?? 0) / 100.0,
            fiveHourResetsAt: fiveHour.resetsAt,
            sevenDayResetsAt: sevenDay.resetsAt,
            sonnetUtilization: sonnetUtilization100.map { $0 / 100.0 },
            sonnetResetsAt: sonnetResetsAt,
            modelLimitName: modelLimitName,
            extraUsage: extra
        )
    }

    /// Parses the model-scoped weekly limit from the top-level `limits` array.
    /// Returns utilization on a 0-100 scale (percent from the API), the reset
    /// date, and the model display name. Prefers the active entry when several
    /// weekly_scoped limits are present.
    private static func parseWeeklyScopedLimit(json: [String: Any]) -> (utilization: Double?, resetsAt: Date?, modelName: String?) {
        guard let limits = json["limits"] as? [[String: Any]] else {
            return (nil, nil, nil)
        }
        let scopedEntries = limits.filter { ($0["kind"] as? String) == "weekly_scoped" }
        guard let entry = scopedEntries.first(where: { ($0["is_active"] as? Bool) == true })
                ?? scopedEntries.first else {
            return (nil, nil, nil)
        }

        // percent may arrive as Int or Double.
        let percent: Double?
        if let d = entry["percent"] as? Double {
            percent = d
        } else if let i = entry["percent"] as? Int {
            percent = Double(i)
        } else {
            percent = nil
        }

        var resetsAt: Date?
        if let dateString = entry["resets_at"] as? String {
            resetsAt = dateFormatter.date(from: dateString)
                ?? dateFormatterNoFraction.date(from: dateString)
        }

        let modelName = (entry["scope"] as? [String: Any])
            .flatMap { $0["model"] as? [String: Any] }
            .flatMap { $0["display_name"] as? String }

        return (percent, resetsAt, modelName)
    }

    private static func findModelBucket(json: [String: Any], containing keyword: String) -> (utilization: Double?, resetsAt: Date?) {
        let lowered = keyword.lowercased()
        for (key, value) in json {
            if key.lowercased().contains(lowered) {
                return parseUtilizationBucket(value)
            }
        }
        return (nil, nil)
    }

    private static func parseUtilizationBucket(_ value: Any?) -> (utilization: Double?, resetsAt: Date?) {
        guard let dict = value as? [String: Any] else { return (nil, nil) }
        let utilization = dict["utilization"] as? Double
        var resetsAt: Date?
        if let dateString = dict["resets_at"] as? String {
            resetsAt = dateFormatter.date(from: dateString)
                ?? dateFormatterNoFraction.date(from: dateString)
        }
        return (utilization, resetsAt)
    }

    private static func parseExtraUsage(_ value: Any?) -> ExtraUsageInfo? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let isEnabled = dict["is_enabled"] as? Bool else { return nil }

        // current_balance may come as Int or Double from API
        let currentBalance: Double?
        if let d = dict["current_balance"] as? Double {
            currentBalance = d
        } else if let i = dict["current_balance"] as? Int {
            currentBalance = Double(i)
        } else {
            currentBalance = nil
        }

        return ExtraUsageInfo(
            isEnabled: isEnabled,
            monthlyLimit: dict["monthly_limit"] as? Double,
            usedCredits: dict["used_credits"] as? Double,
            utilization: dict["utilization"] as? Double,
            currentBalance: currentBalance,
            autoReload: dict["auto_reload"] as? Bool
        )
    }
}
