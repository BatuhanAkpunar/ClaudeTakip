import Testing
import Foundation
@testable import LimitCore

@Suite("Bulut kodlayıcısı")
struct CloudSyncCodecTests {
    @Test("Plan yoksa gövdede açıkça null gider")
    func nilPlanIsNull() throws {
        let sample = QuotaSample(date: Date(timeIntervalSince1970: 1_787_344_332.573), org: "o",
                                 fiveHour: 48, sevenDay: 97, extraUsage: nil)
        let body = try #require(CloudSync.uploadBody([sample], plan: nil))
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("\"plan\":null"))
    }

    @Test("hasMore ve nextSince varsa sonraki sayfa imleci döner")
    func pageWithMore() throws {
        let data = Data(#"{"samples":[{"t":1787344332573,"fiveHour":48,"sevenDay":97,"extra":null}],"hasMore":true,"nextSince":1787344332574}"#.utf8)
        let page = try #require(CloudSync.parsePage(data))
        #expect(page.samples.count == 1)
        #expect(page.next == 1787344332574)
    }

    @Test("hasMore yoksa tek sayfa: imleç nil")
    func pageWithoutMore() throws {
        let data = Data(#"{"samples":[],"nextSince":1787344332574}"#.utf8)
        let page = try #require(CloudSync.parsePage(data))
        #expect(page.samples.isEmpty)
        #expect(page.next == nil)
    }
}
