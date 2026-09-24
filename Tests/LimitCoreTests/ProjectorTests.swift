import Testing
import Foundation
@testable import LimitCore

@Suite("Projeksiyon")
struct ProjectorTests {
    let now = Date(timeIntervalSince1970: 1_787_344_332)
    let deriver = WindowDeriver()
    let projector = Projector()

    @Test("Sabit hızda projeksiyon doğrusal ilerler")
    func linearProjection() throws {
        // Son 30 dk'da %10 artış, yani %20/saat.
        let data = samples([
            (120, 0, 10), (110, 5, 11), (30, 30, 20), (0, 40, 25),
        ], now: now)
        let state = try #require(deriver.derive(.fiveHour, from: data, now: now))
        let p = try #require(projector.project(state, now: now))
        #expect(p.ratePerHour > 15 && p.ratePerHour < 25)
        #expect(p.projectedUtilization > Double(state.utilization))
    }

    @Test("Limit aşılacaksa aşım anı hesaplanır")
    func overrunDetected() throws {
        // %90'da ve saatte %20 gidiyor: 30 dakikada %100.
        let data = samples([
            (180, 0, 10), (60, 70, 20), (30, 80, 22), (0, 90, 25),
        ], now: now)
        let state = try #require(deriver.derive(.fiveHour, from: data, now: now))
        let p = try #require(projector.project(state, now: now))
        let fillAt = try #require(p.fillAt)
        #expect(fillAt > now)
        #expect(fillAt.timeIntervalSince(now) < 2 * 3600)
        // Dolma anı pencerenin sıfırlanmasından önce, yani gerçek bir aşım.
        #expect(p.willOverrun)
    }

    /// Kullanım durunca tahmin ANINDA sıfırlanmaz, zamanla geriler.
    ///
    /// Bilinçli bir denge. Hız artık "son yarım saat" değil "pencere başından
    /// bu yana ortalama": Tahmini Toplam Süre = Geçen Süre × (100 / Kullanım).
    /// Bu, tüm pencere verisini kullanıyor ve tek cümleyle açıklanabiliyor,
    /// ama kullanıcı durduğunda ortalama hemen düşmüyor; geçen süre uzadıkça
    /// kendiliğinden geriliyor. Buradaki test tam olarak o davranışı kilitliyor:
    /// duruşun ardından dolma anı İLERİ gidiyor.
    @Test("Kullanım durunca dolma anı ileri kayıyor")
    func flatUsagePushesFillLater() throws {
        let early = samples([(180, 0, 10), (120, 40, 20)], now: now)
        let earlyState = try #require(deriver.derive(.fiveHour, from: early,
                                                     now: now.addingTimeInterval(-120 * 60)))
        let earlyProjection = try #require(projector.project(
            earlyState, now: now.addingTimeInterval(-120 * 60)))

        // Aynı kullanım, iki saat sonra: hiç harcanmadı.
        let later = samples([(180, 0, 10), (120, 40, 20), (30, 40, 20), (0, 40, 20)], now: now)
        let laterState = try #require(deriver.derive(.fiveHour, from: later, now: now))
        let laterProjection = try #require(projector.project(laterState, now: now))

        #expect(laterProjection.ratePerHour < earlyProjection.ratePerHour)
        let earlyFill = try #require(earlyProjection.fillAt)
        let laterFill = try #require(laterProjection.fillAt)
        #expect(laterFill > earlyFill)
    }

    @Test("Dolma anı pencere dışına düşerse aşım sayılmaz")
    func fillAfterResetIsNotOverrun() throws {
        // Yavaş tempo: pencere kapanmadan %100'e ulaşılmıyor.
        let data = samples([
            (240, 0, 5), (60, 20, 8), (30, 22, 9), (0, 25, 10),
        ], now: now)
        let state = try #require(deriver.derive(.fiveHour, from: data, now: now))
        let p = try #require(projector.project(state, now: now))

        // Hız sıfırdan büyük olduğu için dolma anı yine de hesaplanabilmeli,
        // ama sıfırlanmadan sonraya düştüğü için uyarı üretmemeli.
        let fillAt = try #require(p.fillAt)
        let resetAt = try #require(state.resetAt)
        #expect(fillAt > resetAt)
        #expect(p.willOverrun == false)
    }

    /// Kullanıcının kendi örneği, birebir (2026-09-18):
    /// pencere 1 Eylül 10:00 → 8 Eylül 10:00 (168 saat). 3 Eylül 10:00'da
    /// 48 saat geçmiş, ideal kullanım 48 ÷ 168 × 100 = %28,57, gerçek %40.
    /// Pace = 40 ÷ 28,57 = 1,40×.
    @Test("Pace kullanıcının örneğinde 1,40×")
    func paceMatchesUsersWorkedExample() throws {
        let start = now.addingTimeInterval(-48 * 3600)
        let state = WindowState(kind: .sevenDay, utilization: 40, windowStart: start,
                                resetAt: start.addingTimeInterval(168 * 3600),
                                startUncertainty: 0, isIdle: false, observedResets: [])
        let p = try #require(projector.project(state, now: now))
        let pace = try #require(p.multiplier)
        #expect(abs(pace - 1.40) < 0.005, "pace \(pace)")
        // Bu hızla kota 48 × 100 ÷ 40 = 120. saatte, yani pencere bitmeden biter.
        let fill = try #require(p.fillAt)
        #expect(abs(fill.timeIntervalSince(start) / 3600 - 120) < 0.01)
        #expect(p.willOverrun)
    }

    /// Pace ile "tahmini aşım" aynı soruyu cevaplamalı.
    ///
    /// 2026-09-18: haftalık %93, sıfırlanmaya bir gün varken popover "0,9×
    /// kullanım hızı" ve "Tahmini Aşım 18 Eyl 23:47" diyordu. Pace kullanıcıyı
    /// kendi GEÇMİŞİYLE, tahmin ise KOTAYLA karşılaştırıyordu; yan yana iki
    /// gösterge farklı sorulara cevap verince "ortalamandan yavaşsın ama
    /// taşacaksın" gibi okunamaz bir tablo çıkıyordu. Kullanıcının beklentisi
    /// açık: aşım varsa pace 1'in üstünde.
    ///
    /// Kural: pace ≥ 1 ⇔ aşım. İki pencerede, çok sayıda kullanım/zaman
    /// bileşiminde sınanıyor; pace'in kullanıcının formülüne (gerçek ÷ ideal)
    /// birebir eşit olduğu da her bileşimde doğrulanıyor.
    @Test("Pace 1'i ancak aşım varken geçer")
    func paceAgreesWithOverrun() throws {
        // Sayaçlar testin BOŞUNA geçmediğini kanıtlıyor: pace nil olan
        // bileşimler atlanıyor; hepsi nil olsaydı kural hiç sınanmamış olurdu.
        var checked: [WindowKind: Int] = [:]
        var overruns = 0, safe = 0
        func check(_ state: WindowState, at t: Date) throws {
            let p = try #require(projector.project(state, now: t))
            guard let pace = p.multiplier else { return }
            checked[state.kind, default: 0] += 1
            if p.willOverrun { overruns += 1 } else { safe += 1 }
            let start = try #require(state.windowStart), reset = try #require(state.resetAt)
            let ideal = t.timeIntervalSince(start) / reset.timeIntervalSince(start) * 100
            #expect(abs(pace - Double(state.utilization) / ideal) < 1e-9)
            #expect((pace >= 1) == p.willOverrun,
                    "\(state.kind) %\(state.utilization): pace \(pace), aşım \(p.willOverrun)")
        }

        // 5 saatlik: doğrusal model.
        for used in stride(from: 5, through: 95, by: 10) {
            for hoursIn in [1.0, 2.0, 3.0, 4.0, 4.5] {
                let start = now.addingTimeInterval(-hoursIn * 3600)
                let state = WindowState(kind: .fiveHour, utilization: used, windowStart: start,
                                        resetAt: start.addingTimeInterval(5 * 3600),
                                        startUncertainty: 0, isIdle: false, observedResets: [])
                try check(state, at: now)
            }
        }

        // Haftalık.
        for used in stride(from: 10, through: 95, by: 15) {
            for daysIn in [1.0, 3.0, 5.0, 6.5] {
                let start = now.addingTimeInterval(-daysIn * 86400)
                let state = WindowState(kind: .sevenDay, utilization: used, windowStart: start,
                                        resetAt: start.addingTimeInterval(7 * 86400),
                                        startUncertainty: 0, isIdle: false, observedResets: [])
                try check(state, at: now)
            }
        }

        #expect((checked[.fiveHour] ?? 0) >= 40, "5 saatlik: \(checked[.fiveHour] ?? 0) bileşim")
        #expect((checked[.sevenDay] ?? 0) >= 20, "haftalık: \(checked[.sevenDay] ?? 0) bileşim")
        #expect(overruns >= 10 && safe >= 10, "aşımlı \(overruns), aşımsız \(safe)")
    }
}
