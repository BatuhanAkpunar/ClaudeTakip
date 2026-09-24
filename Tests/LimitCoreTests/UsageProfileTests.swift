import Testing
import Foundation
@testable import LimitCore

@Suite("Kullanım profili")
struct UsageProfileTests {
    private func sample(_ hour: Int, day: Int, fh: Int) -> QuotaSample {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = day
        components.hour = hour; components.minute = 0
        let date = Calendar.current.date(from: components)!
        return QuotaSample(date: date, org: "t", fiveHour: fh, sevenDay: 0, extraUsage: nil)
    }

    @Test("Tüketim yüzdenin artışından okunuyor")
    func readsPositiveDeltas() {
        // 10:00'da %0, 11:00'da %20 → 11. saate 20 puan yazılmalı.
        let profile = UsageProfile.build(from: [
            sample(10, day: 1, fh: 0), sample(11, day: 1, fh: 20),
        ])
        #expect(profile.hourly[11] == 20)
        #expect(profile.hourly[10] == 0)
    }

    @Test("Sıfırlanma tüketim sayılmaz")
    func ignoresResets() {
        // %90'dan %5'e düşüş pencerenin sıfırlanmasıdır, negatif tüketim değil.
        let profile = UsageProfile.build(from: [
            sample(14, day: 1, fh: 90), sample(15, day: 1, fh: 5),
        ])
        #expect(profile.hourly.allSatisfy { $0 == 0 })
    }

    @Test("Uzun boşluklar profile karışmaz")
    func ignoresLongGaps() {
        // 10:00 ile 20:00 arasında uygulama kapalıydı; aradaki artışı tek bir
        // saate yazmak o saati yapay olarak zirve yapardı.
        let profile = UsageProfile.build(from: [
            sample(10, day: 1, fh: 0), sample(20, day: 1, fh: 80),
        ])
        #expect(profile.hourly[20] == 0)
    }

    @Test("Ortalama gün sayısına bölünüyor")
    func averagesAcrossDays() {
        // Aynı saat iki günde gözlendi: 20 ve 40 → ortalama 30 olmalı, toplam 60 değil.
        let profile = UsageProfile.build(from: [
            sample(9, day: 1, fh: 0), sample(10, day: 1, fh: 20),
            sample(9, day: 2, fh: 0), sample(10, day: 2, fh: 40),
        ])
        #expect(profile.hourly[10] == 30)
        #expect(profile.observedDays == 2)
    }

    @Test("Az gözlem güvenilir sayılmıyor")
    func requiresEnoughDays() {
        let thin = UsageProfile.build(from: [sample(9, day: 1, fh: 0), sample(10, day: 1, fh: 5)])
        #expect(thin.isReliable == false)
        #expect(UsageProfile.empty.isReliable == false)
    }

    // MARK: - Tepe saat

    /// Boş profilde `firstIndex(of: 0)` her zaman 0 döndürüyor ve arayüz
    /// "en yoğun saat 00:00" diyordu.
    @Test("Veri yokken tepe saat yok")
    func peakHourEmpty() {
        #expect(UsageProfile.empty.peakHour == nil)

        let profile = UsageProfile(
            hourly: (0..<24).map { $0 == 14 ? 3.0 : 0 },
            hourSampleDays: Array(repeating: 5, count: 24),
            observedDays: 5
        )
        #expect(profile.peakHour == 14)
    }
}
