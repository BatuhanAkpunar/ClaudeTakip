import Foundation

struct PacingTriggerState: Sendable {
    var fastAlertCount: Int = 0
    var criticalAlertFired: Bool = false
    var resetAlertFired: Bool = false

    mutating func resetForNewSession() {
        fastAlertCount = 0
        criticalAlertFired = false
        resetAlertFired = false
    }
}
