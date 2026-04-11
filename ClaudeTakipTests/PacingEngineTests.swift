import Testing
@testable import ClaudeTakip

@Suite struct PacingEngineTests {
    // 5 saatlik pencere = 300 dakika
    private let totalWindow: Double = 300

    // %42 kullanim, 180dk kalmis → gecen sure 120dk, ideal %40
    // Pozisyon sapma: 0.42 - 0.40 = 0.02 → comfortable (<0.03)
    // Rate: delta 0.01 / 3dk = 0.00333, ideal 1/300 = 0.00333, multiplier ~1.0 → steady
    // max(comfortable, steady) = steady
    @Test func steadyWhenOnPace() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.41,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .steady)
    }

    // %40 kullanim, 180dk kalmis → gecen sure 120dk, ideal %40
    // Pozisyon sapma: 0.40 - 0.40 = 0.00 → comfortable
    // Delta 0 → rate comfortable
    @Test func comfortableWhenExactlyOnIdeal() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.40,
            previousUsage: 0.40,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .comfortable)
    }

    // %50 kullanim, 180dk kalmis → gecen sure 120dk, ideal %40
    // Pozisyon sapma: 0.50 - 0.40 = 0.10 → moderate (0.08-0.15)
    @Test func moderateWhenNoticeablyAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.50,
            previousUsage: 0.50,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .moderate)
    }

    // %60 kullanim, 180dk kalmis → gecen sure 120dk, ideal %40
    // Pozisyon sapma: 0.60 - 0.40 = 0.20 → elevated (0.15-0.25)
    @Test func elevatedWhenSignificantlyAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.60,
            previousUsage: 0.60,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .elevated)
    }

    // %80 kullanim, 94dk kalmis → gecen sure 206dk, ideal %68.7
    // Pozisyon sapma: 0.80 - 0.687 = 0.113 → moderate (0.08-0.15)
    @Test func moderateWhenOverIdealButNotElevated() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.80,
            previousUsage: 0.80,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 94        )
        #expect(result == .moderate)
    }

    // %70 kullanim, 180dk kalmis → gecen sure 120dk, ideal %40
    // Pozisyon sapma: 0.70 - 0.40 = 0.30 → high (0.25-0.40)
    @Test func highWhenWayAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.70,
            previousUsage: 0.70,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .high)
    }

    // %90 kullanim, 180dk kalmis → gecen sure 120dk, ideal %40
    // Pozisyon sapma: 0.90 - 0.40 = 0.50 → critical (>=0.40)
    @Test func criticalWhenExtremelyAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.90,
            previousUsage: 0.90,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .critical)
    }

    // Rate testi: delta 0.03, 3dk → rate = 0.01, ideal = 0.00333
    // rateMultiplier = 3.0 → high (2.5-4.0)
    // Pozisyon: 0.42-0.40 = 0.02 → comfortable
    // max(comfortable, high) = high
    @Test func highRateOverridesComfortablePosition() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.39,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .high)
    }

    // Rate testi: delta 0.05, 3dk → rate = 0.01667, ideal = 0.00333
    // rateMultiplier = 5.0 → critical (>=4.0)
    @Test func criticalHighRate() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.45,
            previousUsage: 0.40,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .critical)
    }

    @Test func noPreviousUsage() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: nil,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .unknown)
    }

    @Test func lowRemainingTimeComfortable() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.40,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 5        )
        #expect(result == .comfortable)
    }

    @Test func lowRemainingTimeAndLowQuota() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.95,
            previousUsage: 0.93,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 5        )
        #expect(result == .critical)
    }

    // %80 kullanim, 5dk kalmis → remaining 0.20 > 0.10, < 0.25 → high
    @Test func lowRemainingTimeHighUsage() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.80,
            previousUsage: 0.78,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 5        )
        #expect(result == .high)
    }

    @Test func resetDetected() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.05,
            previousUsage: 0.80,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 300        )
        #expect(result == .comfortable)
    }

    // Rate: delta 0.002, 3dk → rate = 0.000667, ideal = 0.00333
    // rateMultiplier = 0.2 → comfortable (<1.0)
    // Pozisyon: 0.41-0.40 = 0.01 → comfortable (<0.03)
    @Test func comfortableWithVeryLowRate() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.41,
            previousUsage: 0.408,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .comfortable)
    }

    // Steady rate testi: delta 0.004, 3dk → rate = 0.001333, ideal = 0.00333
    // rateMultiplier = 0.4 → comfortable (<1.0)
    // Pozisyon: 0.44-0.40 = 0.04 → steady (0.03-0.08)
    @Test func steadyPositionWithLowRate() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.44,
            previousUsage: 0.44,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180        )
        #expect(result == .steady)
    }

    // Comparable testi
    @Test func paceStatusComparable() {
        #expect(PaceStatus.comfortable < .steady)
        #expect(PaceStatus.steady < .moderate)
        #expect(PaceStatus.moderate < .elevated)
        #expect(PaceStatus.elevated < .high)
        #expect(PaceStatus.high < .critical)
    }
}
