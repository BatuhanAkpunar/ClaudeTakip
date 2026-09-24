import Testing
import Foundation
@testable import LimitCore

@Suite("Servis durumu")
struct StatusServiceTests {
    @Test("Rapor 45 dakikayı GEÇİNCE bayat sayılır")
    func staleBoundary() {
        let t0 = Date(timeIntervalSince1970: 1_787_344_332)
        let report = ServiceStatusReport(status: .operational, description: "All Systems Operational", checkedAt: t0)
        #expect(report.isStale(now: t0.addingTimeInterval(2699)) == false)
        #expect(report.isStale(now: t0.addingTimeInterval(2700)) == false)
        #expect(report.isStale(now: t0.addingTimeInterval(2701)) == true)
    }

    @Test("Aynı durumun yeni okuması eşit sayılmaz")
    func equalityIncludesCheckedAt() {
        let t0 = Date(timeIntervalSince1970: 1_787_344_332)
        let old = ServiceStatusReport(status: .operational, description: "All Systems Operational", checkedAt: t0)
        let fresh = ServiceStatusReport(status: .operational, description: "All Systems Operational",
                                        checkedAt: t0.addingTimeInterval(900))
        #expect(old != fresh)
        #expect(old == old)
    }
}
