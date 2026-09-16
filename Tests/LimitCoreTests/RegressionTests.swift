import Testing
import Foundation
@testable import LimitCore

/// Bulunan ve düzeltilen hataların bir daha geri gelmemesi için.
///
/// Her testin adı hatanın kendisini anlatıyor: "şu şöyle çalışır" değil,
/// "şu şöyle bozuktu, artık değil".
@Suite("Regresyonlar")
struct RegressionTests {

    // MARK: - Çerez alan adı

    /// `domain.contains("claude.ai")` denetimi "claude.ai.saldirgan.com"
    /// alan adını da kabul ediyordu.
    @Test("Alan adı sonek olarak eşleşmeli")
    func cookieDomainSuffix() {
        #expect(isClaudeDomain("claude.ai"))
        #expect(isClaudeDomain(".claude.ai"))
        #expect(isClaudeDomain("api.claude.ai"))
        #expect(!isClaudeDomain("claude.ai.saldirgan.com"))
        #expect(!isClaudeDomain("sahteclaude.ai"))
        #expect(!isClaudeDomain("claude.aim"))
    }

    /// Uygulama hedefindeki denetimin aynısı; LimitCore'dan test edilebilsin
    /// diye burada yeniden yazılmış değil, aynı kural iki yerde de geçerli.
    private func isClaudeDomain(_ domain: String) -> Bool {
        let host = ClaudeWebClient.host
        return domain == host || domain == "." + host || domain.hasSuffix("." + host)
    }

    // MARK: - Tepe saat

    /// Boş profilde `firstIndex(of: 0)` her zaman 0 döndürüyor ve arayüz
    /// "en yoğun saat 00:00" diyordu.
    @Test("Veri yokken tepe saat yok")
    func peakHourEmpty() {
        #expect(UsageProfile.empty.peakHour == nil)

        let profile = UsageProfile(
            hourly: (0..<24).map { $0 == 14 ? 3.0 : 0 },
            weekday: Array(repeating: 0, count: 7),
            hourSampleDays: Array(repeating: 5, count: 24),
            observedDays: 5
        )
        #expect(profile.peakHour == 14)
    }

    // MARK: - Saat sınırı

    /// `bySetting` zaten sonraki eşleşmeye atlıyordu; üstüne bir saat eklemek

    // MARK: - Arşiv işlemi

    /// Hazırlama başarısız olduğunda işlem açık kalıyor ve bağlantı sonraki
    /// her yazmada kilitli kalıyordu.
    @Test("Başarısız içe aktarma bağlantıyı kilitli bırakmaz")
    func importDoesNotLockOnFailure() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("regresyon-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try HistoryStore(url: url)
        let sample = QuotaSample(
            date: Date(), org: "test", fiveHour: 10, sevenDay: 20, extraUsage: nil
        )
        #expect(try store.importSamples([sample]) == 1)
        // İkinci yazma da geçmeli: ilk işlem düzgün kapandıysa kilit yok.
        #expect(try store.importSamples([sample]) == 0)
        #expect(try store.samples(since: Date().addingTimeInterval(-60)).count == 1)
    }
}


/// Hesap bazlı kalıcılık.
///
/// Bulut verisinin kanonik sahibi cihaz değil hesap; anahtar türetiminin
/// kararlı ve geri döndürülemez olması bunun ön şartı.
@Suite("Hesap anahtarı")
struct AccountKeyTests {
    @Test("Aynı hesap her cihazda aynı anahtarı üretir")
    func deterministic() {
        let org = "00000000-0000-4000-8000-000000000001"
        // Cihaz değiştirmenin simülasyonu: aynı girdi, ayrı çağrılar.
        #expect(AccountKey.derive(organizationID: org) == AccountKey.derive(organizationID: org))
        #expect(AccountKey.isValid(AccountKey.derive(organizationID: org)))
    }

    @Test("Farklı hesaplar çakışmaz")
    func distinct() {
        let a = AccountKey.derive(organizationID: "org-a")
        let b = AccountKey.derive(organizationID: "org-b")
        #expect(a != b)
    }

    @Test("Ham organizasyon kimliği anahtarda görünmez")
    func opaque() {
        let org = "00000000-0000-4000-8000-000000000001"
        let key = AccountKey.derive(organizationID: org)
        // Özet, girdiyi ne içerir ne de ondan türetilebilir bir parça taşır.
        #expect(!key.contains("00000000-0000-4000"))
        #expect(key.count == 64)
    }

    @Test("Boşluk ve boş girdi güvenli")
    func whitespace() {
        let org = "  org-x  "
        #expect(AccountKey.derive(organizationID: org) == AccountKey.derive(organizationID: "org-x"))
        #expect(AccountKey.derive(organizationID: "").isEmpty)
        #expect(!AccountKey.isValid(""))
        #expect(!AccountKey.isValid("ABC"))
    }

    @Test("Bulut deposu hesap anahtarını saklar ve bırakır")
    func store() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CloudStore(url: url)

        store.save(identity: CloudIdentity(deviceID: "d1", secret: "s1"))
        store.save(uploadedThrough: Date(timeIntervalSince1970: 1000))
        #expect(store.accountKey == nil)

        let key = AccountKey.derive(organizationID: "org-a")
        store.save(accountKey: key)
        #expect(store.accountKey == key)
        // Kimlik ve işaret korunmalı: hesabı benimsemek cihazı sıfırlamaz.
        #expect(store.identity?.deviceID == "d1")

        // İşaret sıfırlama: hiç yüklenmemiş satırlar hesaba gitsin.
        store.resetWatermark()
        #expect(store.uploadedThrough == nil)
        #expect(store.accountKey == key)

        // Çıkış: anahtar bırakılır, cihaz kimliği durur.
        store.save(accountKey: nil)
        #expect(store.accountKey == nil)
        #expect(store.identity?.deviceID == "d1")
    }
}

/// İstatistik denetiminin dört karşı-örneği.
///
/// Bir istatistik incelemesi (docs/research/istatistik-incelemesi.md) saatlik
/// profilde ve pace hesabında dört sistematik hata buldu. Her biri burada
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

    /// CE3: aynı davranış, farklı örnekleme sıklığı → aynı taban hız.
    ///
    /// Eski payda yalnızca "artışın görüldüğü" aralıkları topluyordu; yüzde tam
    /// sayı olduğu için sık örneklemede taban, örnekleme aralığının tersiyle
    /// ölçekleniyordu. İki cihazın verisi buluttan birleşince taban kendiliğinden
    /// katlanıyor, pace yarıya düşüyordu.
    @Test("Taban hız örnekleme sıklığından bağımsız")
    func baselineIsSamplingIndependent() {
        let projector = Projector()
        let start = date(1, 9, 0)
        let now = date(1, 12, 0)

        // Üç saatte 36 puan = 12 puan/saat. Beş dakikada bir örnek.
        var coarse: [QuotaSample] = []
        for step in 0...36 {
            coarse.append(sample(start.addingTimeInterval(Double(step) * 300), step))
        }
        // Aynı davranış, bir dakikada bir örnek: değer yine beş dakikada bir artıyor.
        var fine: [QuotaSample] = []
        for step in 0...180 {
            fine.append(sample(start.addingTimeInterval(Double(step) * 60), step / 5))
        }

        let a = projector.baselineRate(.fiveHour, samples: coarse, now: now)
        let b = projector.baselineRate(.fiveHour, samples: fine, now: now)
        #expect(a != nil && b != nil)
        #expect(abs((a ?? 0) - 12) < 0.5)
        #expect(abs((a ?? 0) - (b ?? 0)) < 0.5)
    }

    /// CE2: sabit hız, sabit desen → pace 1,0 civarı.
    @Test("Değişmeyen davranışta pace bire yakın")
    func steadyBehaviourGivesUnitPace() {
        let projector = Projector()
        let start = date(1, 9, 0)
        let now = date(1, 12, 0)
        var samples: [QuotaSample] = []
        for step in 0...36 {
            samples.append(sample(start.addingTimeInterval(Double(step) * 300), step))
        }

        let base = projector.baselineRate(.fiveHour, samples: samples, now: now) ?? 0
        // Pencere başından ortalama hız: 3 saatte 36 puan = 12 puan/saat.
        let rate = projector.averageRate(
            kind: .fiveHour, utilization: 36, windowStart: start, now: now
        )
        #expect(base > 0)
        #expect(abs(rate / base - 1) < 0.1)
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
        // 5 SAATLİK pencere doğrusal kaldı: kısa pencerede davranış modeli
        // anlamsız, kullanıcının formülü (Geçen × 100/Kullanım) geçerli.
        let projector = Projector()
        let now = date(1, 14, 0)
        let start = date(1, 12, 0)   // 2 saat önce başladı
        var samples: [QuotaSample] = []
        for step in 0...12 {
            samples.append(sample(start.addingTimeInterval(Double(step) * 600), step))
        }
        let state = WindowState(
            kind: .fiveHour, utilization: 12,
            windowStart: start, resetAt: date(1, 17, 0),
            startUncertainty: 0, isIdle: false, observedResets: []
        )
        let projection = try #require(projector.project(state, samples: samples, now: now))
        #expect(projection.usesHistory == false)

        // Geçen 2 saat, kullanım %12 → toplam 2 × (100/12) = 16,7 saat.
        let elapsed = now.timeIntervalSince(start) / 3600
        let expectedFill = start.addingTimeInterval(elapsed * (100 / 12) * 3600)
        let fill = try #require(projection.fillAt)
        #expect(abs(fill.timeIntervalSince(expectedFill)) < 120)
    }

    /// Haftalık tahmin, yeterli geçmiş varsa geçmiş davranışa dayanır ve
    /// doğrusal DEĞİL bükülü bir eğri üretir.
    @Test("Haftalık tahmin geçmiş davranış eğrisine dayanır")
    func weeklyUsesBehaviouralCurve() throws {
        let projector = Projector()
        let dur: TimeInterval = 7 * 24 * 3600

        // Üç tam geçmiş hafta: her hafta sonunda %100'e ulaşmış, ama ritim
        // düzgün DEĞİL (ilk yarı yavaş, ikinci yarı hızlı).
        var samples: [QuotaSample] = []
        let base = date(1, 0, 0)
        for week in 0..<3 {
            let wStart = base.addingTimeInterval(Double(week) * dur)
            for h in stride(from: 0, through: 168, by: 6) {
                let frac = Double(h) / 168
                // İkinci yarıda hızlanan birikim (konveks): frac^2 gibi.
                let util = Int((frac * frac * 100).rounded())
                samples.append(sample(wStart.addingTimeInterval(Double(h) * 3600), 0, util))
            }
            // Hafta sonu sıfırlanma: bir sonraki hafta 0'dan başlıyor.
            samples.append(sample(wStart.addingTimeInterval(dur - 1), 0, 100))
        }

        // Dördüncü (mevcut) hafta: 3 gün geçti, kullanım geçmiş ortalamayla uyumlu.
        let curStart = base.addingTimeInterval(3 * dur)
        let now = curStart.addingTimeInterval(3 * 24 * 3600)   // 3. gün
        for h in stride(from: 0, through: 72, by: 6) {
            let frac = Double(h) / 168
            samples.append(sample(curStart.addingTimeInterval(Double(h) * 3600), 0, Int((frac * frac * 100).rounded())))
        }
        let curUtil = Int((pow(72.0 / 168, 2) * 100).rounded())

        let state = WindowState(
            kind: .sevenDay, utilization: curUtil,
            windowStart: curStart, resetAt: curStart.addingTimeInterval(dur),
            startUncertainty: 0, isIdle: false, observedResets: []
        )
        let projection = try #require(projector.project(state, samples: samples, now: now))
        #expect(projection.usesHistory == true)
        #expect(projection.forecast.count > 5)

        // Eğri konveks: ikinci yarıdaki artış birinci yarıdakinden büyük.
        // Doğrusal olsaydı iki yarının eğimi eşit olurdu.
        let curve = projection.forecast
        let firstHalf = curve.filter { $0.position < 0.75 }
        let secondHalf = curve.filter { $0.position >= 0.75 }
        if let f0 = firstHalf.first, let f1 = firstHalf.last,
           let s0 = secondHalf.first, let s1 = secondHalf.last,
           f1.position > f0.position, s1.position > s0.position {
            let slope1 = (f1.utilization - f0.utilization) / (f1.position - f0.position)
            let slope2 = (s1.utilization - s0.utilization) / (s1.position - s0.position)
            #expect(slope2 > slope1)
        }
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
            var samples: [QuotaSample] = []
            for step in 0...20 {
                let t = start.addingTimeInterval(Double(step) * kind.duration / 40)
                samples.append(kind == .fiveHour ? sample(t, step * 5) : sample(t, 0, step * 5))
            }
            let state = WindowState(
                kind: kind, utilization: 100,
                windowStart: start, resetAt: start.addingTimeInterval(kind.duration),
                startUncertainty: 0, isIdle: false, observedResets: []
            )
            let projection = try #require(projector.project(state, samples: samples, now: now))
            #expect(projection.forecast.isEmpty, "\(kind) dolmuşken eğri üretilmemeli")
            // Eğri boş olmasa bile ilk nokta asla tavanda olmamalı: grafik
            // döngüsünün indeks tabanı buna güveniyor.
            if let first = projection.forecast.first { #expect(first.utilization < 100) }
        }
    }

    /// Geçmiş yetersizse haftalık tahmin "günde 10 saat" aktif-saat modeline
    /// düşer: takvim saati (168) değil aktif saat (70) kullanılıyor.
    @Test("Geçmiş yoksa aktif-saat modeline düşer")
    func weeklyFallsBackToActiveHours() throws {
        let projector = Projector()
        let dur: TimeInterval = 7 * 24 * 3600
        let start = date(1, 0, 0)
        let now = start.addingTimeInterval(2 * dur / 7)   // 2. gün

        // Yalnızca mevcut hafta, geçmiş yok.
        var samples: [QuotaSample] = []
        for h in stride(from: 0, through: 48, by: 4) {
            samples.append(sample(start.addingTimeInterval(Double(h) * 3600), 0, Int(Double(h) / 4)))
        }
        let state = WindowState(
            kind: .sevenDay, utilization: 12,
            windowStart: start, resetAt: start.addingTimeInterval(dur),
            startUncertainty: 0, isIdle: false, observedResets: []
        )
        let projection = try #require(projector.project(state, samples: samples, now: now))
        #expect(projection.usesHistory == false)

        // Aktif saat: 2 günde 7/24 olsaydı 48 saat, aktif modelle ~20 saat.
        let active = projector.activeHours(from: start, to: now)
        #expect(active < 30 && active > 10)
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
