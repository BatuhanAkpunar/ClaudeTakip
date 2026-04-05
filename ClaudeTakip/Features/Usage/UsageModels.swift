import Foundation

struct UsageData: Sendable {
    let fiveHourUtilization: Double   // 0-1 range (API returns 0-100, divided by 100 during parse)
    let sevenDayUtilization: Double   // 0-1 range
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?

    // Model-specific buckets
    let sonnetUtilization: Double?
    let sonnetResetsAt: Date?
    // Extra usage (overage billing)
    let extraUsage: ExtraUsageInfo?

    var sessionRemaining: Double { max(0, 1.0 - fiveHourUtilization) }

    /// Convert to CachedUsage (for writing to disk)
    func toCachedUsage() -> CachedUsage {
        CachedUsage(
            fiveHour: UsageBucket(utilization: fiveHourUtilization, resetsAt: fiveHourResetsAt),
            sevenDay: UsageBucket(utilization: sevenDayUtilization, resetsAt: sevenDayResetsAt),
            sevenDaySonnet: sonnetUtilization.map { UsageBucket(utilization: $0, resetsAt: sonnetResetsAt) },
            extraUsage: extraUsage
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
        let sonnet = findModelBucket(json: json, containing: "sonnet")
        let extra = parseExtraUsage(json["extra_usage"])

        guard fiveHour.utilization != nil || sevenDay.utilization != nil else {
            throw UsageParseError.missingFields
        }

        return UsageData(
            fiveHourUtilization: (fiveHour.utilization ?? 0) / 100.0,
            sevenDayUtilization: (sevenDay.utilization ?? 0) / 100.0,
            fiveHourResetsAt: fiveHour.resetsAt,
            sevenDayResetsAt: sevenDay.resetsAt,
            sonnetUtilization: sonnet.utilization.map { $0 / 100.0 },
            sonnetResetsAt: sonnet.resetsAt,
            extraUsage: extra
        )
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
