import Testing
import Foundation
@testable import LimitCore

/// Test verisi, kullanıcının gerçek `plan-usage-history.json` dosyasından alınan
/// desenleri taklit eder: 5 dakikalık örnekleme, sıfırlanmada yüzdenin düşmesi.
private func samples(_ pairs: [(minutesAgo: Int, fh: Int, sd: Int)], now: Date) -> [QuotaSample] {
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
}

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
        func check(_ state: WindowState, _ data: [QuotaSample], at t: Date) throws {
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
                try check(state, [], at: now)
            }
        }

        // Haftalık.
        for used in stride(from: 10, through: 95, by: 15) {
            for daysIn in [1.0, 3.0, 5.0, 6.5] {
                let start = now.addingTimeInterval(-daysIn * 86400)
                let state = WindowState(kind: .sevenDay, utilization: used, windowStart: start,
                                        resetAt: start.addingTimeInterval(7 * 86400),
                                        startUncertainty: 0, isIdle: false, observedResets: [])
                try check(state, [], at: now)
            }
        }

        #expect((checked[.fiveHour] ?? 0) >= 40, "5 saatlik: \(checked[.fiveHour] ?? 0) bileşim")
        #expect((checked[.sevenDay] ?? 0) >= 20, "haftalık: \(checked[.sevenDay] ?? 0) bileşim")
        #expect(overruns >= 10 && safe >= 10, "aşımlı \(overruns), aşımsız \(safe)")
    }
}

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

@Suite("Sunucu istemcisi")
struct ClaudeWebClientTests {
    @Test("Organizasyon seçimi API-only org'u atlar")
    func picksChatOrganization() {
        let list: [[String: Any]] = [
            ["uuid": "api-org", "capabilities": ["api"]],
            ["uuid": "chat-org", "capabilities": ["chat", "claude_pro"]],
        ]
        // İlk elemanı almak API-only org'u seçerdi ve kota tablosu boş gelirdi.
        #expect(ClaudeWebClient.selectOrganization(from: list) == "chat-org")
    }

    @Test("Yetenek bilgisi yoksa ilk organizasyona düşülür")
    func fallsBackToFirst() {
        let list: [[String: Any]] = [["uuid": "only-org"]]
        #expect(ClaudeWebClient.selectOrganization(from: list) == "only-org")
    }

    @Test("Cüzdan tutarları sentten çevrilir")
    func walletConvertsCents() throws {
        let json: [String: Any] = [
            "extra_usage": [
                "is_enabled": true,
                "monthly_limit": 2050,
                "used_credits": 347,
                "utilization": 16.9,
            ],
        ]
        let wallet = try #require(ServerUsage(json: json).wallet)
        #expect(wallet.monthlyLimit == 20.50)
        #expect(wallet.usedCredits == 3.47)
        #expect(wallet.utilization == 16.9)
    }

    @Test("Sıfır aylık tavan limitsiz demek, sayı olarak gösterilmez")
    func zeroLimitMeansUnlimited() throws {
        let json: [String: Any] = [
            "extra_usage": ["is_enabled": true, "monthly_limit": 0, "used_credits": 100],
        ]
        let wallet = try #require(ServerUsage(json: json).wallet)
        #expect(wallet.monthlyLimit == nil)
        #expect(wallet.usedCredits == 1.0)
    }

    @Test("seven_day_omelette ayrı bir kota olarak sayılmaz")
    func omeletteIsNotASeparateQuota() {
        let json: [String: Any] = [
            "seven_day": ["utilization": 15.0],
            "seven_day_omelette": ["utilization": 15.0],
            "seven_day_sonnet": ["utilization": 1.0],
        ]
        let usage = ServerUsage(json: json)
        // Aynı havuz iki kez listelenirse kartta çift görünüyordu.
        #expect(usage.modelWindows["Fable"] == nil)
        #expect(usage.modelWindows["Sonnet"] != nil)
        #expect(usage.sevenDay?.utilization == 15.0)
    }
}

@Suite("Kalıcı arşiv")
struct HistoryStoreTests {
    private func makeStore() throws -> (HistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudetakip-test-\(UUID().uuidString).sqlite")
        return (try HistoryStore(url: url), url)
    }

    private func sample(_ secondsAgo: Int, fh: Int, sd: Int, xu: Int? = nil) -> QuotaSample {
        QuotaSample(
            date: Date(timeIntervalSince1970: 1_787_000_000 - Double(secondsAgo)),
            org: "test", fiveHour: fh, sevenDay: sd, extraUsage: xu
        )
    }

    @Test("Örnekler yazılır ve geri okunur")
    func roundTrip() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let inserted = try store.importSamples([
            sample(300, fh: 10, sd: 5),
            sample(0, fh: 20, sd: 6, xu: 100),
        ])
        #expect(inserted == 2)

        let read = try store.samples(since: Date(timeIntervalSince1970: 0))
        #expect(read.count == 2)
        #expect(read.last?.extraUsage == 100)
        #expect(read.first?.fiveHour == 10)
    }

    @Test("Aynı örnek iki kez yazılmaz")
    func importIsIdempotent() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let batch = [sample(300, fh: 10, sd: 5), sample(0, fh: 20, sd: 6)]
        #expect(try store.importSamples(batch) == 2)
        // Kota dosyası her okumada baştan geliyor; ikinci içe aktarma
        // arşivi büyütmemeli.
        #expect(try store.importSamples(batch) == 0)
        #expect(store.stats().count == 2)
    }

    @Test("Tarih filtresi eski kayıtları eler")
    func filtersBySince() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.importSamples([sample(3600, fh: 1, sd: 1), sample(0, fh: 9, sd: 9)])
        let recent = try store.samples(since: Date(timeIntervalSince1970: 1_787_000_000 - 60))
        #expect(recent.count == 1)
        #expect(recent.first?.fiveHour == 9)
    }
}

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

    @Test("Beklenen tüketim saatlerin toplamı")
    func expectedConsumptionSums() {
        let profile = UsageProfile.build(from: [
            sample(9, day: 1, fh: 0), sample(10, day: 1, fh: 10),
            sample(10, day: 1, fh: 10), sample(11, day: 1, fh: 30),
        ])
        // 10. saat 10 puan, 11. saat 20 puan.
        #expect(profile.expectedConsumption(hours: [10, 11]) == 30)
    }
}

@Suite("Oturum saklama")
struct SessionStoreTests {
    private func makeStore() -> (SessionStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ct-session-\(UUID().uuidString).json")
        // Keychain'e dokunmamak için teste özel servis adı.
        let keychain = KeychainStore(service: "ClaudeTakipTest-\(UUID().uuidString)", account: "t")
        return (SessionStore(url: url, keychain: keychain), url)
    }

    @Test("Oturum yazılıp geri okunuyor")
    func roundTrip() throws {
        let (store, url) = makeStore()
        defer { store.clear(); try? FileManager.default.removeItem(at: url) }

        let session = SessionStore.Session(sessionKey: "sk-ant-sid02-abc", organizationID: "org-9")
        // Bu iddia bir hatadan doğdu: `.completeFileProtection` macOS'ta yazmayı
        // engelliyordu ve kaydetme sessizce başarısız oluyordu.
        #expect(store.save(session))

        let read = try #require(store.load())
        #expect(read.sessionKey == session.sessionKey)
        #expect(read.organizationID == "org-9")
    }

    @Test("Temizlenince oturum kalmıyor")
    func clearRemoves() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.save(SessionStore.Session(sessionKey: "sk-x", organizationID: nil))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("Dosya yoksa nil döner, çökmez")
    func missingFile() {
        let store = SessionStore(
            url: URL(fileURLWithPath: "/nonexistent/dir/session.json"),
            keychain: KeychainStore(service: "ClaudeTakipTest-missing", account: "t")
        )
        #expect(store.load() == nil)
    }

    @Test("Kaydedilen dosya yalnızca sahibine açık")
    func fileIsPrivate() throws {
        let (store, url) = makeStore()
        defer { store.clear(); try? FileManager.default.removeItem(at: url) }

        store.save(SessionStore.Session(sessionKey: "sk-secret", organizationID: nil))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(permissions == 0o600)
    }
}

@Suite("Saatlik tahmin")
struct HourlyProjectionTests {
    let projector = Projector()
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25; c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    private func profile(_ hourly: [Int: Double]) -> UsageProfile {
        var values = [Double](repeating: 0, count: 24)
        for (h, v) in hourly { values[h] = v }
        return UsageProfile(
            hourly: values,
            weekday: Array(repeating: 0, count: 8),
            hourSampleDays: Array(repeating: 10, count: 24),
            observedDays: 10
        )
    }
}
