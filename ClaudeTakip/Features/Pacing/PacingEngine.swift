import Foundation

enum PacingEngine {
    static func calculatePaceStatus(
        currentUsage: Double,
        previousUsage: Double?,
        totalWindowMinutes: Double,
        remainingMinutes: Double,
        pollIntervalMinutes: Double
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

        // Instantaneous rate check (only if there is a meaningful delta)
        let rateSeverity: PaceStatus
        if delta > 0.001 {
            let idealRate = 1.0 / totalWindowMinutes
            let actualRate = delta / pollIntervalMinutes
            let rateMultiplier = actualRate / idealRate

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

        let baseSeverity = max(positionSeverity, rateSeverity)

        // Absolute usage floor — "comfortable" is misleading at high usage
        if currentUsage > 0.85 {
            return max(baseSeverity, .moderate)
        } else if currentUsage > 0.70 {
            return max(baseSeverity, .steady)
        }

        return baseSeverity
    }
}
