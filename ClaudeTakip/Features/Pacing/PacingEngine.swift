import Foundation

enum PacingEngine {
    static func calculatePaceStatus(
        currentUsage: Double,
        previousUsage: Double?,
        totalWindowMinutes: Double,
        remainingMinutes: Double,
        weeklyUsage: Double = 0
    ) -> PaceStatus {
        guard previousUsage != nil else { return .unknown }

        let remaining = 1.0 - currentUsage
        let delta = currentUsage - (previousUsage ?? 0)

        // Reset detection
        if delta < 0 { return .comfortable }

        // Very little time remaining — only look at remaining quota
        if remainingMinutes < PacingConstants.minRemainingMinutes {
            if remaining < PacingConstants.criticalRemainingThreshold {
                return .critical
            }
            return remaining < 0.25 ? .high : .comfortable
        }

        // Position check: where are we relative to the ideal line?
        let elapsedFraction = max(0, 1.0 - (remainingMinutes / totalWindowMinutes))
        let positionDeviation = currentUsage - elapsedFraction

        let positionSeverity: PaceStatus
        switch positionDeviation {
        case ..<PacingConstants.steadyPositionThreshold:
            positionSeverity = .comfortable
        case PacingConstants.steadyPositionThreshold..<PacingConstants.moderatePositionThreshold:
            positionSeverity = .steady
        case PacingConstants.moderatePositionThreshold..<PacingConstants.elevatedPositionThreshold:
            positionSeverity = .moderate
        case PacingConstants.elevatedPositionThreshold..<PacingConstants.highPositionThreshold:
            positionSeverity = .elevated
        case PacingConstants.highPositionThreshold..<PacingConstants.criticalPositionThreshold:
            positionSeverity = .high
        default:
            positionSeverity = .critical
        }

        // Overall rate check: average speed across the session (matches the UI speed multiplier)
        let rateSeverity: PaceStatus
        if elapsedFraction > 0.01 && currentUsage > 0.005 {
            let rateMultiplier = currentUsage / elapsedFraction

            switch rateMultiplier {
            case ..<PacingConstants.steadyRateThreshold:
                rateSeverity = .comfortable
            case PacingConstants.steadyRateThreshold..<PacingConstants.moderateRateThreshold:
                rateSeverity = .steady
            case PacingConstants.moderateRateThreshold..<PacingConstants.elevatedRateThreshold:
                rateSeverity = .moderate
            case PacingConstants.elevatedRateThreshold..<PacingConstants.highRateThreshold:
                rateSeverity = .elevated
            case PacingConstants.highRateThreshold..<PacingConstants.criticalRateThreshold:
                rateSeverity = .high
            default:
                rateSeverity = .critical
            }
        } else {
            rateSeverity = .comfortable
        }

        var severity = max(positionSeverity, rateSeverity)

        // Session usage floor
        if currentUsage > 0.80 {
            severity = max(severity, .moderate)
        } else if currentUsage > 0.65 {
            severity = max(severity, .steady)
        }

        // Weekly usage floor — ensures box color reflects weekly concerns too
        if weeklyUsage > 0.70 {
            severity = max(severity, .moderate)
        }

        return severity
    }
}
