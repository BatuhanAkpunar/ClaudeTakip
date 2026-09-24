import Testing
import Foundation
@testable import LimitCore

@Suite("Tazelik")
struct FreshnessTests {
    let now = Date(timeIntervalSince1970: 1_787_344_332)

    @Test("Yaş eşikleri doğru sınıflandırılır")
    func thresholds() {
        #expect(Freshness(lastUpdate: now.addingTimeInterval(-120), now: now) == .live(now.addingTimeInterval(-120)))
        #expect(Freshness(lastUpdate: now.addingTimeInterval(-20 * 60), now: now).isStale == false)
        #expect(Freshness(lastUpdate: now.addingTimeInterval(-60 * 60), now: now).isStale)
    }
}
