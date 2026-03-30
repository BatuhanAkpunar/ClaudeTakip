import Foundation

enum PacingEngine {
    static func calculatePaceStatus(
        currentUsage: Double,
        previousUsage: Double?,
        remainingMinutes: Double,
        pollIntervalMinutes: Double
    ) -> PaceStatus {
        guard let previousUsage else { return .unknown }

        let remaining = 1.0 - currentUsage
        let delta = currentUsage - previousUsage

        // Reset algilama
        if delta < 0 { return .comfortable }

        // Kalan sure cok az — sadece kalan hakka bak
        if remainingMinutes < PacingConstants.minRemainingMinutes {
            return remaining < PacingConstants.criticalRemainingThreshold ? .critical : .comfortable
        }

        // Delta 0 ise degisiklik yok
        if delta == 0 { return .comfortable }

        // Sapma carpani
        let idealRate = remaining / remainingMinutes
        let actualRate = delta / pollIntervalMinutes

        guard idealRate > 0 else { return .critical }
        let deviationMultiplier = actualRate / idealRate

        switch deviationMultiplier {
        case ..<PacingConstants.comfortableThreshold: return .comfortable
        case PacingConstants.comfortableThreshold..<PacingConstants.balancedThreshold: return .balanced
        case PacingConstants.balancedThreshold..<PacingConstants.fastThreshold: return .fast
        default: return .critical
        }
    }
}
