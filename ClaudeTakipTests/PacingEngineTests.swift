import Testing
@testable import ClaudeTakip

@Suite struct PacingEngineTests {
    // 5 saatlik pencere = 300 dakika
    private let totalWindow: Double = 300

    // %42 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.42 - 0.40 = 0.02 → comfortable (<0.03)
    // Rate: 0.42/0.40 = 1.05 → steady (1.0..<1.3)
    // max(comfortable, steady) = steady
    @Test func steadyWhenOnPace() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.41,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .steady)
    }

    // %40 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.00 → comfortable
    // Rate: 0.40/0.40 = 1.00 → steady (lower bound of 1.0..<1.3)
    // max(comfortable, steady) = steady
    @Test func steadyWhenExactlyOnIdeal() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.40,
            previousUsage: 0.40,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .steady)
    }

    // %50 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.50 - 0.40 = 0.10 → moderate (0.08..<0.15)
    // Rate: 0.50/0.40 = 1.25 → steady (1.0..<1.3)
    // max(moderate, steady) = moderate
    @Test func moderateWhenNoticeablyAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.50,
            previousUsage: 0.50,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .moderate)
    }

    // %60 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.60 - 0.40 = 0.20 → elevated (0.15..<0.25)
    // Rate: 0.60/0.40 = 1.50 → moderate (1.3..<1.8)
    // max(elevated, moderate) = elevated
    @Test func elevatedWhenSignificantlyAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.60,
            previousUsage: 0.60,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .elevated)
    }

    // %80 kullanim, 94dk kalmis → elapsedFraction ~0.687
    // Pozisyon sapma: 0.80 - 0.687 = 0.113 → moderate (0.08..<0.15)
    // Rate: 0.80/0.687 = 1.165 → steady (1.0..<1.3)
    // max(moderate, steady) = moderate
    @Test func moderateWhenOverIdealButNotElevated() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.80,
            previousUsage: 0.80,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 94
        )
        #expect(result == .moderate)
    }

    // %70 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.70 - 0.40 = 0.30 → high (0.25..<0.40)
    // Rate: 0.70/0.40 = 1.75 → moderate (1.3..<1.8)
    // max(high, moderate) = high
    @Test func highWhenWayAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.70,
            previousUsage: 0.70,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .high)
    }

    // %90 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.90 - 0.40 = 0.50 → critical (>=0.40)
    // Rate: 0.90/0.40 = 2.25 → elevated (1.8..<2.5)
    // max(critical, elevated) = critical
    @Test func criticalWhenExtremelyAhead() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.90,
            previousUsage: 0.90,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .critical)
    }

    // Rate'in position'a göre daha yüksek severity ürettigi senaryo (early session burst):
    // currentUsage=0.27, remaining=240 → elapsedFraction 0.20
    // Pozisyon sapma: 0.27 - 0.20 = 0.07 → steady (0.03..<0.08)
    // Rate: 0.27/0.20 = 1.35 → moderate (1.3..<1.8)
    // max(steady, moderate) = moderate — rate, severity'yi yukari cekti
    @Test func rateRaisesSeverityAboveSteadyPosition() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.27,
            previousUsage: 0.27,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 240
        )
        #expect(result == .moderate)
    }

    @Test func noPreviousUsage() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: nil,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .unknown)
    }

    @Test func lowRemainingTimeComfortable() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.40,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 5
        )
        #expect(result == .comfortable)
    }

    @Test func lowRemainingTimeAndLowQuota() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.95,
            previousUsage: 0.93,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 5
        )
        #expect(result == .critical)
    }

    // %80 kullanim, 5dk kalmis → remaining 0.20 > 0.10, < 0.25 → high
    @Test func lowRemainingTimeHighUsage() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.80,
            previousUsage: 0.78,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 5
        )
        #expect(result == .high)
    }

    @Test func resetDetected() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.05,
            previousUsage: 0.80,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 300
        )
        #expect(result == .comfortable)
    }

    // %41 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.41 - 0.40 = 0.01 → comfortable
    // Rate: 0.41/0.40 = 1.025 → steady (1.0..<1.3)
    // max(comfortable, steady) = steady
    @Test func steadyWhenJustAboveIdeal() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.41,
            previousUsage: 0.408,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
        #expect(result == .steady)
    }

    // %44 kullanim, 180dk kalmis → elapsedFraction 0.40
    // Pozisyon sapma: 0.44 - 0.40 = 0.04 → steady (0.03..<0.08)
    // Rate: 0.44/0.40 = 1.10 → steady (1.0..<1.3)
    // max(steady, steady) = steady
    @Test func steadyPositionWithLowRate() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.44,
            previousUsage: 0.44,
            totalWindowMinutes: totalWindow,
            remainingMinutes: 180
        )
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
