import Testing
import Foundation
@testable import LimitCore

/// İstatistik denetiminin karşı-örnekleri.
///
/// Bir istatistik incelemesi (docs/research/istatistik-incelemesi.md) saatlik
/// profilde ve pace hesabında sistematik hatalar buldu. Her biri burada
/// sayısal karşı-örneğiyle kilitleniyor.
@Suite("İstatistik karşı-örnekleri")
struct StatisticsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 6, day: day,
            hour: hour, minute: minute
        ))!
    }

    private func sample(_ d: Date, _ five: Int, _ seven: Int = 0) -> QuotaSample {
        QuotaSample(date: d, org: "t", fiveHour: five, sevenDay: seven, extraUsage: nil)
    }

    /// CE1: 20 gün 14:00'te düzenli çalışma, tek bir gece 03:00'te patlama.
    ///
    /// Eski payda "tüketimin olduğu gün" olduğu için 03:00 ortalaması 40,
    /// 14:00 ortalaması 20 çıkıyor ve kadran nadir gece saatini "en yoğun"
    /// ilan ediyordu.
    @Test("Nadir gece patlaması en yoğun saati çalmaz")
    func peakHourIsNotStolenByRareBurst() {
        var samples: [QuotaSample] = []
        for day in 1...20 {
            samples.append(sample(date(day, 14, 0), 0))
            samples.append(sample(date(day, 14, 30), 20))
        }
        samples.append(sample(date(21, 3, 0), 0))
        samples.append(sample(date(21, 3, 30), 40))

        let profile = UsageProfile.build(from: samples, calendar: calendar)
        #expect(profile.peakHour == 14)
        // Gece saati tamamen silinmiyor, yalnızca gününe yayılıyor.
        #expect(profile.hourly[3] > 0)
        #expect(profile.hourly[14] > profile.hourly[3])
    }

    /// CE4: bir dakikalık aralıktan hız türetilmemeli.
    ///
    /// Yüzde tam sayı: bir dakikada görülen tek puanlık artış saatte 60 puana
    /// karşılık geliyor ve pace'i uçuruyordu.
    @Test("Çok kısa ölçümden hız türetilmez")
    func tooShortSpanYieldsNoRate() {
        let projector = Projector()
        let now = date(1, 12, 0)
        // Pencere bir dakika önce başladı, kullanım %1.
        let rate = projector.averageRate(
            kind: .fiveHour, utilization: 1,
            windowStart: now.addingTimeInterval(-60), now: now
        )
        #expect(rate == 0)
    }

    /// Tahmin kuralı: Tahmini Toplam Süre = Geçen Süre × (100 / Kullanım).
    /// Dolma anı ile ortalama hızdan türetilen an birebir aynı olmalı.
    @Test("Dolma anı kullanıcının formülüyle birebir aynı")
    func fillTimeMatchesFormula() throws {
        // Kullanıcının formülü: Tahmini Toplam Süre = Geçen × 100 / Kullanım.
        let projector = Projector()
        let now = date(1, 14, 0)
        let start = date(1, 12, 0)   // 2 saat önce başladı
        let state = WindowState(
            kind: .fiveHour, utilization: 12,
            windowStart: start, resetAt: date(1, 17, 0),
            startUncertainty: 0, isIdle: false, observedResets: []
        )
        let projection = try #require(projector.project(state, now: now))

        // Geçen 2 saat, kullanım %12 → toplam 2 × (100/12) = 16,7 saat.
        let elapsed = now.timeIntervalSince(start) / 3600
        let expectedFill = start.addingTimeInterval(elapsed * (100 / 12) * 3600)
        let fill = try #require(projection.fillAt)
        #expect(abs(fill.timeIntervalSince(expectedFill)) < 120)
    }

    /// Sıfırlanma kuralı: gürültü sıfırlanma değil, boşluk sıfırlanmadır.
    @Test("Sıfırlanma kuralı düşük değer gürültüsünü elemeli, boşluğu saymalı")
    func resetRuleHandlesNoiseAndGaps() {
        let fiveHour: TimeInterval = 5 * 3600

        // (a) Düşük değerli gerileme sıfırlanma DEĞİL: seride üç kaynak
        // karışıyor ve bir puanlık fark yuvarlama gürültüsü.
        #expect(!ResetRule.didReset(previous: 1, current: 0, gap: 60, duration: fiveHour))
        #expect(!ResetRule.didReset(previous: 3, current: 1, gap: 60, duration: fiveHour))

        // (b) Anlamlı birikimin sıfıra düşmesi sıfırlanmadır.
        #expect(ResetRule.didReset(previous: 72, current: 0, gap: 60, duration: fiveHour))
        #expect(ResetRule.didReset(previous: 40, current: 15, gap: 60, duration: fiveHour))

        // (c) Pencere boyundan uzun boşluk, değer DÜŞMESE bile sıfırlanmadır:
        // uygulama kapalıyken pencere döndü. Eskiden bu tümüyle görünmezdi ve
        // iki ayrı pencere tek pencere gibi birleşiyordu.
        #expect(ResetRule.didReset(previous: 40, current: 45, gap: fiveHour + 60, duration: fiveHour))
        #expect(!ResetRule.didReset(previous: 40, current: 45, gap: fiveHour - 60, duration: fiveHour))
    }

    /// Uzun boşluktan sonra pencere yeniden başlamalı: aksi halde geçen süre
    /// olduğundan uzun ölçülüp hız ve tahmin aşağı kayıyor.
    @Test("Uzun boşluk pencereyi böler")
    func longGapSplitsWindow() throws {
        let deriver = WindowDeriver()
        let start = date(1, 8, 0)
        var samples: [QuotaSample] = []
        // İlk pencere: 8:00-10:00, %40'a kadar.
        for step in 0...8 {
            samples.append(sample(start.addingTimeInterval(Double(step) * 900), step * 5))
        }
        // 6 saatlik boşluk (5 saatlik pencereden uzun), sonra yeniden kullanım.
        let after = start.addingTimeInterval(8 * 900 + 6 * 3600)
        for step in 0...4 {
            samples.append(sample(after.addingTimeInterval(Double(step) * 900), 45 + step))
        }
        let now = after.addingTimeInterval(4 * 900)
        let state = try #require(deriver.derive(.fiveHour, from: samples, now: now))
        // Pencere boşluktan SONRA başlamalı, 8:00'de değil.
        let windowStart = try #require(state.windowStart)
        #expect(windowStart >= after, "boşluk sonrası pencere yeni başlamalı")
    }

    /// Pencere %100'e dolduğunda tahmin eğrisi ÜRETİLMEMELİ.
    ///
    /// Üretilirse eğrinin ilk noktası tam 100 oluyor ve grafik onu "tavanı
    /// kesen nokta" sanıp bir önceki noktayı okumaya çalışıyordu: dizide
    /// indeks -1. Çökme tam da kullanıcının limiti dolduğu için popover'ı
    /// açtığı anda oluşuyordu.
    @Test("Dolmuş pencerede tahmin eğrisi üretilmez")
    func fullWindowProducesNoForecastCurve() throws {
        let projector = Projector()
        for kind in [WindowKind.fiveHour, .sevenDay] {
            let start = date(1, 0, 0)
            let now = start.addingTimeInterval(kind.duration / 2)
            let state = WindowState(
                kind: kind, utilization: 100,
                windowStart: start, resetAt: start.addingTimeInterval(kind.duration),
                startUncertainty: 0, isIdle: false, observedResets: []
            )
            let projection = try #require(projector.project(state, now: now))
            #expect(projection.forecast.isEmpty, "\(kind) dolmuşken eğri üretilmemeli")
            // Eğri boş olmasa bile ilk nokta asla tavanda olmamalı: grafik
            // döngüsünün indeks tabanı buna güveniyor.
            if let first = projection.forecast.first { #expect(first.utilization < 100) }
        }
    }

    /// A6: kaynaklar arası bir puanlık gürültü sıfırlanma sayılmamalı.
    ///
    /// Tek seride üç kaynak karışabiliyor (Desktop dosyası, sunucu okuması,
    /// buluttan gelen ikinci cihaz). Yuvarlama farkı pencereyi ortasından
    /// kesiyordu.
    @Test("Bir puanlık gerileme sıfırlanma sayılmaz")
    func noiseIsNotAReset() {
        let deriver = WindowDeriver()
        let start = date(1, 9, 0)
        // 40'tan 60'a tırmanış; ortada 52 → 51 gibi tek puanlık bir gerileme.
        let values = [40, 44, 47, 52, 51, 55, 58, 60]
        let samples = values.enumerated().map { index, value in
            sample(start.addingTimeInterval(Double(index) * 600), value)
        }
        let state = deriver.derive(.fiveHour, from: samples, now: start.addingTimeInterval(4200))
        #expect(state?.observedResets.isEmpty == true)
        #expect(state?.windowStart == start)

        // Gerçek sıfırlanma hâlâ yakalanmalı: 60'tan 1'e düşüş.
        let withReset = samples + [sample(start.addingTimeInterval(4800), 1)]
        let after = deriver.derive(.fiveHour, from: withReset, now: start.addingTimeInterval(5400))
        #expect(after?.observedResets.count == 1)
    }

    /// Haftalık pencere sıfırlandıktan hemen sonra 20 dakikalık veriden
    /// 7 günlük tahmin üretilmemeli.
    ///
    /// Gerçek gözlem: pencere 11:12'de sıfırlandı, 12:35'te %2'ydi ve uygulama
    /// "pencere sonunda %668" diyordu. Asgari ölçüm süresi pencere boyuyla
    /// ölçeklenmediği sürece her haftalık sıfırlanma bunu üretiyor.
    @Test("Taze haftalık pencereden tahmin üretilmez")
    func freshWeeklyWindowHasNoProjection() {
        let projector = Projector()
        let start = date(1, 11, 12)
        let now = date(1, 12, 35)   // 23 dakika sonra, kullanım %2
        let rate = projector.averageRate(
            kind: .sevenDay, utilization: 2, windowStart: start, now: now
        )
        #expect(rate == 0)

        // 5 saatlik pencerede aynı süre YETERLİ: eşik pencereyle ölçekli.
        let fiveRate = projector.averageRate(
            kind: .fiveHour, utilization: 2, windowStart: start, now: now
        )
        #expect(fiveRate > 0)
    }
}
