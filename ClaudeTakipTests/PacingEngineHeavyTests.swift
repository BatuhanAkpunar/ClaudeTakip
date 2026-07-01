import Testing
@testable import ClaudeTakip

/// Heavy boundary coverage for PacingEngine. Every expectation is derived by
/// hand from the thresholds in PacingConstants, targeting the exact edges where
/// severity classification flips.
@Suite struct PacingEngineHeavyTests {
    private let total: Double = 300 // 5-hour window in minutes

    // MARK: - Reset / recovery detection

    // NOTE: any downward tick returns .comfortable (reset/recovery detection).
    // This is intentional but lenient — even a 1% dip at 97% usage reads as
    // comfortable. Flagged for review; this test pins the current behavior.
    @Test func anyDownwardTickReadsComfortableEvenAtHighUsage() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.97, previousUsage: 0.98,
            totalWindowMinutes: total, remainingMinutes: 180
        )
        #expect(result == .comfortable)
    }

    @Test func noPreviousUsageIsUnknown() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.90, previousUsage: nil,
            totalWindowMinutes: total, remainingMinutes: 60
        )
        #expect(result == .unknown)
    }

    // MARK: - Low-remaining-time branch (< 10 min)

    // remaining minutes == 10 is NOT < 10, so it uses the main pacing path.
    // 50% used with ~97% elapsed → well under pace → comfortable.
    @Test func exactlyTenMinutesUsesMainPath() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.50, previousUsage: 0.50,
            totalWindowMinutes: total, remainingMinutes: 10
        )
        #expect(result == .comfortable)
    }

    // 9 min left, 5% quota remaining (< 0.10) → critical
    @Test func lowTimeCriticalWhenQuotaNearlyGone() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.95, previousUsage: 0.94,
            totalWindowMinutes: total, remainingMinutes: 9
        )
        #expect(result == .critical)
    }

    // 5 min left, ~0.15 quota remaining (in (0.10, 0.25)) → high.
    // NB: use an interior value — 0.90 usage yields 1-0.90 = 0.0999…8 < 0.10
    // (IEEE-754), which correctly classifies as critical, not a boundary "high".
    @Test func lowTimeHighWhenModestQuotaLeft() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.85, previousUsage: 0.84,
            totalWindowMinutes: total, remainingMinutes: 5
        )
        #expect(result == .high)
    }

    // 5 min left, exactly 0.25 quota remaining → not < 0.25 → comfortable
    @Test func lowTimeComfortableAtQuarterQuotaBoundary() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.75, previousUsage: 0.74,
            totalWindowMinutes: total, remainingMinutes: 5
        )
        #expect(result == .comfortable)
    }

    // MARK: - Position deviation lower bounds (remaining 180 → elapsed 0.40)

    @Test func positionSteadyBucket() { // dev 0.05 → steady (0.03..<0.08)
        #expect(pace(0.45, 180) == .steady)
    }

    @Test func positionModerateBucket() { // dev 0.09 → moderate (0.08..<0.15)
        #expect(pace(0.49, 180) == .moderate)
    }

    @Test func positionElevatedLowerBound() { // dev 0.15
        #expect(pace(0.55, 180) == .elevated)
    }

    @Test func positionHighLowerBound() { // dev 0.25
        #expect(pace(0.65, 180) == .high)
    }

    @Test func positionCriticalLowerBound() { // dev 0.40
        #expect(pace(0.80, 180) == .critical)
    }

    // MARK: - Rate can dominate position

    // 20% used at only 10% elapsed → dev 0.10 (moderate) but rate 2.0 (elevated)
    @Test func rateDominatesWhenBurstingEarly() {
        #expect(pace(0.20, 270) == .elevated)
    }

    // MARK: - Usage floors

    // On-pace at 82% → raw steady, but the >0.80 floor lifts it to moderate
    @Test func sessionFloorAboveEightyLiftsToModerate() {
        // remaining 54 → elapsed 0.82, dev ~0
        #expect(pace(0.82, 54) == .moderate)
    }

    // Under pace at 70% → raw comfortable, but the >0.65 floor lifts to steady
    @Test func sessionFloorAboveSixtyFiveLiftsToSteady() {
        // remaining 60 → elapsed 0.80, dev -0.10, rate 0.875 → comfortable raw
        #expect(pace(0.70, 60) == .steady)
    }

    // Comfortable session but 75% weekly → weekly floor lifts to moderate
    @Test func weeklyFloorLiftsComfortableToModerate() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.20, previousUsage: 0.20,
            totalWindowMinutes: total, remainingMinutes: 60,
            weeklyUsage: 0.75
        )
        #expect(result == .moderate)
    }

    // MARK: - Above-100% usage in the main path

    @Test func usageAboveOneHundredPercentIsCritical() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 1.10, previousUsage: 1.05,
            totalWindowMinutes: total, remainingMinutes: 180
        )
        #expect(result == .critical)
    }

    // Helper: steady previous (delta 0) so we exercise the pacing path, not reset.
    private func pace(_ usage: Double, _ remaining: Double) -> PaceStatus {
        PacingEngine.calculatePaceStatus(
            currentUsage: usage, previousUsage: usage,
            totalWindowMinutes: total, remainingMinutes: remaining
        )
    }
}
