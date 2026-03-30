import Testing
@testable import ClaudeKota

@Suite struct PacingEngineTests {
    @Test func calculateComfortable() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.41,
            remainingMinutes: 180,
            pollIntervalMinutes: 3
        )
        #expect(result == .comfortable)
    }

    @Test func calculateCritical() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.39,
            remainingMinutes: 180,
            pollIntervalMinutes: 3
        )
        #expect(result == .critical)
    }

    @Test func noPreviousUsage() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: nil,
            remainingMinutes: 180,
            pollIntervalMinutes: 3
        )
        #expect(result == .unknown)
    }

    @Test func zeroDelta() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.42,
            remainingMinutes: 180,
            pollIntervalMinutes: 3
        )
        #expect(result == .comfortable)
    }

    @Test func lowRemainingTime() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.42,
            previousUsage: 0.40,
            remainingMinutes: 5,
            pollIntervalMinutes: 3
        )
        #expect(result == .comfortable)
    }

    @Test func lowRemainingTimeAndLowQuota() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.95,
            previousUsage: 0.93,
            remainingMinutes: 5,
            pollIntervalMinutes: 3
        )
        #expect(result == .critical)
    }

    @Test func resetDetected() {
        let result = PacingEngine.calculatePaceStatus(
            currentUsage: 0.05,
            previousUsage: 0.80,
            remainingMinutes: 300,
            pollIntervalMinutes: 3
        )
        #expect(result == .comfortable)
    }
}
