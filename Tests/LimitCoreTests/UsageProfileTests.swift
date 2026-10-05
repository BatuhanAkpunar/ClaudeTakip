import Testing
import Foundation
@testable import LimitCore

@Suite("Kullanım profili")
struct UsageProfileTests {
    private func sample(_ hour: Int, _ minute: Int = 0, day: Int, fh: Int, org: String = "t") -> QuotaSample {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = day
        components.hour = hour; components.minute = minute
        let date = Calendar.current.date(from: components)!
        return QuotaSample(date: date, org: org, fiveHour: fh, sevenDay: 0, extraUsage: nil)
    }

    @Test("Tüketim aralığın orta noktasının saatine yazılır")
    func readsPositiveDeltas() {
        // 10:00 %0 → 11:00 %20: iş 10:00-11:00 arasında, orta nokta 10:30.
        let profile = UsageProfile.build(from: [
            sample(10, day: 1, fh: 0), sample(11, day: 1, fh: 20),
        ])
        #expect(profile.hourly[10] > 0)
        #expect(profile.hourly[11] == 0)
        #expect(abs(profile.intensity[10] - 20) < 1e-9)
    }

    @Test("Saat sonundaki iş bir sonraki saate kaymaz")
    func endOfHourWorkStaysInItsHour() {
        // Her gün 13:55-14:00 arası çalışılıyor. Eskiden artış bitiş
        // örneğinin saatine (14) yazılıyor ve 13 sıfır görünüyordu.
        let samples = (1...4).flatMap { day in
            [sample(13, 55, day: day, fh: 0), sample(14, 0, day: day, fh: 30)]
        }
        let profile = UsageProfile.build(from: samples)
        #expect(profile.peakHour == 13)
        #expect(profile.hourly[14] == 0)
    }

    @Test("Sıfırlanma tüketim sayılmaz")
    func ignoresResets() {
        // %90'dan %5'e düşüş pencerenin sıfırlanmasıdır, negatif tüketim değil.
        let profile = UsageProfile.build(from: [
            sample(14, day: 1, fh: 90), sample(15, day: 1, fh: 5),
        ])
        #expect(profile.hourly.allSatisfy { $0 == 0 })
        #expect(profile.peakHour == nil)
    }

    @Test("Uzun boşluklar profile karışmaz")
    func ignoresLongGaps() {
        // 10:00 ile 20:00 arasında uygulama kapalıydı; aradaki artışı bir
        // saate yazmak o saati yapay olarak zirve yapardı.
        let profile = UsageProfile.build(from: [
            sample(10, day: 1, fh: 0), sample(20, day: 1, fh: 80),
        ])
        #expect(profile.hourly.allSatisfy { $0 == 0 })
    }

    @Test("Pay, saatin gözlendiği günler üzerinden; yakın günler ağır basar")
    func averagesAcrossDays() {
        // Aynı saat iki günde aktif: 20 ve 40 puan.
        let profile = UsageProfile.build(from: [
            sample(9, day: 1, fh: 0), sample(10, day: 1, fh: 20),
            sample(9, day: 2, fh: 0), sample(10, day: 2, fh: 40),
        ])
        #expect(profile.observedDays == 2)
        // İki gün gözlendi ama payda en az 3 gün: tek tük görülen saat %100 olmasın.
        #expect(profile.hourly[9] < 1)
        // Ortalama 30'un üstünde: dünkü 40 önceki günün 20'sinden ağır.
        #expect(profile.intensity[9] > 30 && profile.intensity[9] < 40)
    }

    @Test("Tek bir yoğun gece her gün çalışılan saati geçemez")
    func singleBurstDoesNotWin() {
        // Üç gün de 14:00'te az; ikinci gün bir kez 02:00'de çok.
        var samples: [QuotaSample] = []
        for day in 1...3 {
            if day == 2 { samples += [sample(2, day: day, fh: 20), sample(2, 30, day: day, fh: 80)] }
            samples += [sample(14, day: day, fh: 0), sample(14, 30, day: day, fh: 5)]
        }
        let profile = UsageProfile.build(from: samples)
        #expect(profile.isReliable)
        #expect(profile.peakHour == 14)
        #expect(profile.hourly[14] > profile.hourly[2])
        // Büyüklük kaybolmuyor: ayrıntı tablosunda 02:00 daha yoğun.
        #expect(profile.intensity[2] > profile.intensity[14])
    }

    @Test("Farklı org'ların örnekleri birbirine karışmaz")
    func orgsAreChainedSeparately() {
        // Hesap A ve B aynı saatte araya giriyor. Eskiden A→B farkı (75)
        // hayalet tüketim sayılıyor, A'nın gerçek +5'i hiç hesaplanmıyordu.
        let profile = UsageProfile.build(from: [
            sample(10, 0, day: 1, fh: 5, org: "A"),
            sample(10, 5, day: 1, fh: 80, org: "B"),
            sample(10, 10, day: 1, fh: 10, org: "A"),
            sample(10, 15, day: 1, fh: 80, org: "B"),
        ])
        #expect(abs(profile.intensity[10] - 5) < 1e-9)
    }

    @Test("Aynı tüketimi gören iki kaynak ikiye katlanmaz")
    func duplicateSourcesAreNotSummed() {
        // Aynı hesap, iki etiket (Desktop dosyası ve sunucu okuması).
        let profile = UsageProfile.build(from: [
            sample(10, 0, day: 1, fh: 0, org: "desktop"),
            sample(10, 1, day: 1, fh: 0, org: "server"),
            sample(10, 20, day: 1, fh: 10, org: "desktop"),
            sample(10, 21, day: 1, fh: 10, org: "server"),
        ])
        #expect(abs(profile.intensity[10] - 10) < 1e-9)
    }

    @Test("Saat, örneğin kaydedildiği andaki yerel saatten okunur")
    func storedOffsetSurvivesTimezoneChange() throws {
        // İstanbul'da (UTC+3) 10:00-10:20 arası çalışıldı = 07:00-07:20 UTC.
        let start = try #require(ISO8601DateFormatter().date(from: "2026-08-03T07:00:00Z"))
        let samples = [
            QuotaSample(date: start, org: "t", fiveHour: 0, sevenDay: 0, extraUsage: nil),
            QuotaSample(date: start.addingTimeInterval(1200), org: "t", fiveHour: 10, sevenDay: 0, extraUsage: nil),
        ]
        // Kullanıcı artık Los Angeles'ta. Kayıtlı fark kullanılınca saat 10
        // kalmalı; kullanılmazsa gece yarısına kayardı.
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        let stored = UsageProfile.build(from: samples, utcOffsets: [10_800, 10_800], calendar: losAngeles)
        #expect(stored.hourly[10] > 0)
        #expect(stored.hourly[0] == 0)

        let legacy = UsageProfile.build(from: samples, calendar: losAngeles)
        #expect(legacy.hourly[0] > 0)
    }

    @Test("Hafta günü × saat matrisi doğru satıra yazılır")
    func weekdayGrid() {
        let first = sample(9, day: 3, fh: 0)
        let profile = UsageProfile.build(from: [first, sample(9, 30, day: 3, fh: 10)])
        let row = (Calendar.current.component(.weekday, from: first.date) + 5) % 7
        #expect(profile.weekdayHourly[row][9] > 0)
        #expect(profile.weekdaySampleDays[row][9] == 1)
        for other in 0..<7 where other != row {
            #expect(profile.weekdayHourly[other][9] == 0)
        }
    }

    @Test("Eski alışkanlık yeni alışkanlığın önüne geçmez")
    func recentDaysWeighMore() {
        // Ağustos başında beş gün 09:00, ayın sonunda beş gün 15:00.
        var samples: [QuotaSample] = []
        for day in 1...5 { samples += [sample(9, day: day, fh: 0), sample(9, 30, day: day, fh: 10)] }
        for day in 25...29 { samples += [sample(15, day: day, fh: 0), sample(15, 30, day: day, fh: 10)] }
        let profile = UsageProfile.build(from: samples)
        #expect(profile.peakHour == 15)
        #expect(profile.hourly[15] > profile.hourly[9])
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
            hourly: (0..<24).map { $0 == 14 ? 0.5 : 0 },
            hourSampleDays: Array(repeating: 5, count: 24),
            observedDays: 5
        )
        #expect(profile.peakHour == 14)
    }

    @Test("Eşit paylarda yoğun saat kazanır")
    func peakTieBreaksOnIntensity() {
        let profile = UsageProfile(
            hourly: (0..<24).map { $0 == 9 || $0 == 21 ? 0.8 : 0 },
            intensity: (0..<24).map { $0 == 21 ? 30 : 10 },
            hourSampleDays: Array(repeating: 5, count: 24),
            observedDays: 5
        )
        #expect(profile.peakHour == 21)
    }
}

@Suite("Aktivite doğruluk regresyonları")
struct ActivityRegressionTests {
    let start = Date(timeIntervalSince1970: 1_786_320_000) // 2026-08-10 00:00 UTC (Monday)
    func sample(_ minutes: Int, _ five: Int, _ seven: Int = 0) -> QuotaSample {
        QuotaSample(date: start.addingTimeInterval(Double(minutes) * 60), org: "a",
                    fiveHour: five, sevenDay: seven, extraUsage: nil)
    }
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    @Test("Geriye düşüp aynı değere gelen okuma hayalet aktivite üretmez")
    func staleReadRecovery() {
        let p = UsageProfile.build(from: [sample(0, 40), sample(5, 39), sample(10, 40)], calendar: calendar)
        #expect(p.peakHour == nil)
        #expect(p.intensity.allSatisfy { $0 == 0 })
        let real = UsageProfile.build(from: [sample(0, 40), sample(5, 39), sample(10, 42)], calendar: calendar)
        #expect(abs(real.intensity.reduce(0, +) - 2) < 1e-9)
    }

    @Test("Sıfırlanma sonrası tüketim yeni tabandan sayılır")
    func resetStartsNewBaseline() {
        let p = UsageProfile.build(from: [sample(0, 90), sample(5, 0), sample(10, 5)], calendar: calendar)
        #expect(abs(p.intensity.reduce(0, +) - 5) < 1e-9)
    }

    @Test("5 saatlik sıfırlanmada haftalık artış aktiviteyi kurtarır")
    func weeklyIncreaseProvesActivity() {
        let p = UsageProfile.build(from: [sample(0, 90, 20), sample(5, 5, 21)], calendar: calendar)
        #expect(p.peakHour != nil)
        // Eski 90 ile yeni 5 arasındaki tüketim bilinemez; uydurulmaz.
        #expect(p.intensity.allSatisfy { $0 == 0 })
        #expect(p.forecastHourly.reduce(0, +) > 0)
    }

    @Test("Her hafta günü UTC farkı uygulandıktan sonra doğru satıra girer")
    func allWeekdaysAndMidnight() {
        for day in 0..<7 {
            let a = sample(day * 1440 + 22 * 60, 0)
            let b = sample(day * 1440 + 22 * 60 + 30, 5)
            let p = UsageProfile.build(from: [a, b], utcOffsets: [10800, 10800], calendar: calendar)
            let localDate = a.date.addingTimeInterval(10800)
            let weekday = (calendar.component(.weekday, from: localDate) + 5) % 7
            #expect(p.weekdaySampleDays[weekday][1] == 1)
            #expect(p.weekdayHourly[weekday][1] > 0)
            #expect(p.hourly[1] > 0)
            #expect(p.intensity[1] == 5)
            #expect(p.weekdaySampleDays.flatMap { $0 }.reduce(0, +) == 1)
        }
    }

    @Test("Saat dilimi değişen aralık yanlış saate yazılmaz")
    func offsetTransitionIsUnknown() {
        let p = UsageProfile.build(from: [sample(0, 0), sample(30, 10)],
                                   utcOffsets: [10800, 7200], calendar: calendar)
        #expect(p == .empty)
    }
}
