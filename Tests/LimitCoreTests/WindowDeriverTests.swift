import Testing
import Foundation
@testable import LimitCore

/// Test verisi, kullanıcının gerçek `plan-usage-history.json` dosyasından alınan
/// desenleri taklit eder: 5 dakikalık örnekleme, sıfırlanmada yüzdenin düşmesi.
func samples(_ pairs: [(minutesAgo: Int, fh: Int, sd: Int)], now: Date) -> [QuotaSample] {
    pairs
        .map { QuotaSample(
            date: now.addingTimeInterval(TimeInterval(-$0.minutesAgo * 60)),
            org: "test",
            fiveHour: $0.fh,
            sevenDay: $0.sd,
            extraUsage: nil
        ) }
        .sorted { $0.date < $1.date }
}

@Suite("Pencere türetme")
struct WindowDeriverTests {
    let now = Date(timeIntervalSince1970: 1_787_344_332)
    let deriver = WindowDeriver()

    @Test("Yüzdedeki her düşüş bir sıfırlanma olarak sayılır")
    func detectsResets() throws {
        let data = samples([
            (100, 41, 50), (95, 1, 50), (90, 12, 51),   // 5 saatlik sıfırlandı
            (85, 22, 52), (80, 30, 52),
        ], now: now)
        let state = try #require(deriver.derive(.fiveHour, from: data, now: now))
        #expect(state.observedResets.count == 1)
        #expect(state.utilization == 30)
    }

    @Test("Sıfırlanmadan sonraki ilk kullanım pencerenin başlangıcıdır")
    func windowStartsAtFirstUse() throws {
        // 60 dk önce sıfırlandı, 50 dk önce kullanım başladı.
        let data = samples([
            (70, 77, 90), (60, 0, 90), (50, 10, 91), (40, 17, 92), (0, 48, 97),
        ], now: now)
        let state = try #require(deriver.derive(.fiveHour, from: data, now: now))

        // Başlangıç, sıfır örneği ile ilk aktif örnek arasının ortasında olmalı.
        let expected = now.addingTimeInterval(-55 * 60)
        let start = try #require(state.windowStart)
        #expect(abs(start.timeIntervalSince(expected)) < 60)

        // Sıfırlanma başlangıçtan tam 5 saat sonra.
        let reset = try #require(state.resetAt)
        #expect(abs(reset.timeIntervalSince(start) - 5 * 3600) < 1)
    }

    @Test("Kullanım hiç başlamadıysa pencere boşta sayılır")
    func idleWindow() throws {
        let data = samples([(30, 55, 40), (20, 0, 40), (10, 0, 40), (0, 0, 40)], now: now)
        let state = try #require(deriver.derive(.fiveHour, from: data, now: now))
        #expect(state.isIdle)
        #expect(state.resetAt == nil)
    }

    @Test("Haftalık sıfırlanma gözlemden zincirlenir, kestirilmez")
    func weeklyChainsFromObservation() throws {
        // 2 gün önce haftalık sıfırlandı. Sonraki sıfırlanma tam 7 gün sonrası olmalı.
        let twoDays = 2 * 24 * 60
        let data = samples([
            (twoDays + 10, 20, 100), (twoDays, 20, 0), (twoDays - 10, 21, 3), (0, 48, 97),
        ], now: now)
        let state = try #require(deriver.derive(.sevenDay, from: data, now: now))
        let reset = try #require(state.resetAt)
        let observed = try #require(state.observedResets.first)
        #expect(abs(reset.timeIntervalSince(observed) - 7 * 24 * 3600) < 1)
        // Sıfırlanma gelecekte olmalı, geçmişte değil.
        #expect(reset > now)
    }

    @Test("Boş girdi çökmez")
    func emptyInput() {
        #expect(deriver.derive(.fiveHour, from: [], now: now) == nil)
    }

    @Test("Sunucu değerinden kurulan pencere yuvarlanır ve geriye sayılır")
    func fromServerRounds() throws {
        let reset = now.addingTimeInterval(2 * 3600)
        let state = WindowState.fromServer(kind: .fiveHour, utilization: 47.6, resetsAt: reset)
        #expect(state.utilization == 48)
        let start = try #require(state.windowStart)
        #expect(start == reset.addingTimeInterval(-5 * 3600))
        #expect(state.resetAt == reset)
        #expect(state.startUncertainty == 0)
        #expect(state.isIdle == false)
        #expect(state.observedResets.isEmpty)
    }

    @Test("Sunucu sınırıyla düzeltme: başlangıç geriye sayılır, yüzde yuvarlanır")
    func correctedByServer() throws {
        let reset = now.addingTimeInterval(2 * 3600)
        let observed = [now.addingTimeInterval(-6 * 3600)]
        let local = WindowState(kind: .fiveHour, utilization: 30, windowStart: now.addingTimeInterval(-3600),
                                resetAt: nil, startUncertainty: 300, isIdle: false, observedResets: observed)
        #expect(local.corrected(by: nil) == local)
        #expect(local.corrected(by: ServerUsage.Window(utilization: 50, resetsAt: nil)) == local)

        let fixed = local.corrected(by: ServerUsage.Window(utilization: 47.6, resetsAt: reset))
        #expect(fixed.windowStart == reset.addingTimeInterval(-5 * 3600))
        #expect(fixed.resetAt == reset)
        #expect(fixed.startUncertainty == 0)
        #expect(fixed.utilization == 48)
        #expect(fixed.isIdle == false)
        #expect(fixed.observedResets == observed)

        let idle = local.corrected(by: ServerUsage.Window(utilization: 0.4, resetsAt: reset))
        #expect(idle.utilization == 0)
        #expect(idle.isIdle)
    }
}
