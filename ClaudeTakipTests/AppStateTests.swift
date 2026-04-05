import Testing
@testable import ClaudeTakip

@Suite struct AppStateTests {
    @Test @MainActor func defaultState() {
        let state = AppState()
        #expect(state.isLoggedIn == false)
        #expect(state.sessionRemaining == 1.0)
        #expect(state.sessionUsage == 0)
        #expect(state.weeklyUsage == 0)
        #expect(state.paceStatus == .unknown)
        #expect(state.connectionStatus == .disconnected)
        #expect(state.claudeSystemStatus == .operational)
        #expect(state.manualRefreshCount == 0)
    }

    @Test @MainActor func sessionRemainingCalculation() {
        let state = AppState()
        state.sessionUsage = 0.42
        state.sessionRemaining = 1.0 - state.sessionUsage
        #expect(abs(state.sessionRemaining - 0.58) < 0.0001)
    }
}
