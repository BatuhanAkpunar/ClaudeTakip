import Testing
import Foundation
@testable import LimitCore

@Suite("Sunucu yeniden deneme politikası")
struct ServerRetryPolicyTests {
    let now = Date(timeIntervalSince1970: 1_787_344_332)

    @Test("Geri çekilme merdiveni 1-2-5-15-30 dakika ve tavanda kalır")
    func ladder() {
        var policy = ServerRetryPolicy()
        var delays: [TimeInterval] = []
        for _ in 0..<6 {
            policy.backOff(now: now)
            delays.append(policy.nextAttempt!.timeIntervalSince(now))
        }
        #expect(delays == [60, 120, 300, 900, 1800, 1800])
        #expect(policy.failureStreak == 5)
    }

    @Test("Beş kısa denemeden sonra geri çekilir ve sayaç sıfırlanır")
    func quickRetries() {
        var policy = ServerRetryPolicy()
        for _ in 0..<5 {
            #expect(policy.recordTransientFailure(now: now) == .retrySoon)
        }
        #expect(policy.quickRetryCount == 5)
        #expect(policy.recordTransientFailure(now: now) == .backedOff)
        #expect(policy.quickRetryCount == 0)
        #expect(policy.nextAttempt == now.addingTimeInterval(60))
    }

    @Test("Otomatik deneme tam sınır anında serbest, bir saniye önce değil")
    func gate() {
        var policy = ServerRetryPolicy()
        #expect(policy.allowsAutomaticAttempt(at: now))
        policy.backOff(now: now)
        let next = now.addingTimeInterval(60)
        #expect(policy.allowsAutomaticAttempt(at: next))
        #expect(!policy.allowsAutomaticAttempt(at: next.addingTimeInterval(-1)))
    }

    @Test("clearBackoff kısa deneme sayacına dokunmaz")
    func clearKeepsQuickCount() {
        var policy = ServerRetryPolicy()
        _ = policy.recordTransientFailure(now: now)
        _ = policy.recordTransientFailure(now: now)
        policy.backOff(now: now)
        policy.clearBackoff()
        #expect(policy.quickRetryCount == 2)
        #expect(policy.failureStreak == 0)
        #expect(policy.nextAttempt == nil)
    }
}
