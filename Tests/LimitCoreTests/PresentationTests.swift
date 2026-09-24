import Testing
import Foundation
@testable import LimitCore

// Bu testler UTC saat dilimini varsayıyor (CI `TZ=UTC` ile çalıştırıyor):
// sıfırlanma cümleleri ve saat etiketleri yerel saatle biçimleniyor. Dil her
// testte Türkçeye sabitleniyor ve her `make` çağrısı sabit bir `now` alıyor.
@Suite("Sunum")
struct PresentationTests {
    /// 19 Eylül 2026 06:26:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_789_799_160)

    private static func turkish(_ body: () -> Void) {
        L.$languageOverride.withValue(.turkish) { body() }
    }

    // MARK: - Cüzdan

    @Test("Cüzdan: galerideki yedi durum")
    func walletGallery() {
        let renewal = "1 Ekimde sıfırlanır"
        let cases: [(String, WalletState, WalletPresentation)] = [
            ("Harcanıyor",
             WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 32,
                         monthlyLimit: 50, usedCredits: 16.20, remainingBalance: 33.80, currency: "USD",
                         autoReloadEnabled: true),
             WalletPresentation(
                status: "Açık", statusTone: .calm,
                barFraction: min(16.20 / (16.20 + 33.80), 1), barTone: .calm,
                heroValue: "$33,80", heroLabel: nil, detail: "$16,20 harcandı", amounts: nil,
                renewalDate: renewal, autoReload: true,
                help: "Ekstra kullanım açık. Harcanan ve kalan bakiye, toplamı bütçeni verir.")),
            ("Tavan aşıldı",
             WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 100,
                         monthlyLimit: 50, usedCredits: 62.40, remainingBalance: 0, currency: "USD",
                         autoReloadEnabled: true),
             WalletPresentation(
                status: "Açık", statusTone: .calm,
                barFraction: 1, barTone: .danger,
                heroValue: "$0,00", heroLabel: nil, detail: "$62,40 harcandı", amounts: nil,
                renewalDate: renewal, autoReload: true,
                help: "Ekstra kullanım açık. Harcanan ve kalan bakiye, toplamı bütçeni verir.")),
            ("Hazır",
             WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 0,
                         monthlyLimit: 50, usedCredits: 0, remainingBalance: 50, currency: "USD",
                         autoReloadEnabled: false),
             WalletPresentation(
                status: "Açık", statusTone: .calm,
                barFraction: 0, barTone: .calm,
                heroValue: "$50,00", heroLabel: nil, detail: "$0,00 harcandı", amounts: nil,
                renewalDate: renewal, autoReload: false,
                help: "Ekstra kullanım açık. Harcanan ve kalan bakiye, toplamı bütçeni verir.")),
            ("Tavan doldu",
             WalletState(isEnabled: false, disabledReason: nil, consumedPercent: 100, spendLimitReached: true,
                         monthlyLimit: 2, usedCredits: 13.83, remainingBalance: 9.18, currency: "USD",
                         autoReloadEnabled: false),
             WalletPresentation(
                status: "Tavan doldu", statusTone: .warn,
                barFraction: nil, barTone: .calm,
                heroValue: "$9,18", heroLabel: nil, detail: nil, amounts: nil,
                renewalDate: renewal, autoReload: false,
                help: "Aylık tavana ulaşıldığı için kullanım duraklatıldı. Kalan $9,18 bakiye, yeniden açılınca geçerli.")),
            ("Uyuyan bakiye",
             WalletState(isEnabled: false, disabledReason: nil, consumedPercent: nil,
                         monthlyLimit: nil, usedCredits: nil, remainingBalance: 34.50, currency: "USD",
                         autoReloadEnabled: false),
             WalletPresentation(
                status: "Kapalı", statusTone: .muted,
                barFraction: nil, barTone: .calm,
                heroValue: "$34,50", heroLabel: nil, detail: nil, amounts: nil,
                renewalDate: renewal, autoReload: false,
                help: "Ekstra kullanım kapalı, harcama olmuyor. Cüzdanda $34,50 duruyor.")),
            ("Yalnız yüzde",
             WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 100),
             WalletPresentation(
                status: "Açık", statusTone: .calm,
                barFraction: 1, barTone: .danger,
                heroValue: nil, heroLabel: nil, detail: nil,
                amounts: "giriş yapınca tutarlar görünür",
                renewalDate: renewal, autoReload: nil,
                help: "Yüzde yerel dosyadan geliyor. Tutarlar ve kalan bakiye için giriş gerekiyor.")),
            ("Kapalı",
             WalletState(isEnabled: false, disabledReason: "ekstra kullanım kapalı", consumedPercent: nil),
             WalletPresentation(
                status: "Kapalı", statusTone: .muted,
                barFraction: nil, barTone: .calm,
                heroValue: nil, heroLabel: nil, detail: nil,
                amounts: "ekstra kullanım kapalı",
                renewalDate: nil, autoReload: nil,
                help: "Ekstra kullanım kapalı. Abonelik limitin dolduğunda Claude durur, kredi harcanmaz.")),
        ]
        Self.turkish {
            for (name, state, expected) in cases {
                #expect(WalletPresentation.make(state, now: Self.now) == expected, "\(name)")
            }
        }
    }

    @Test("Cüzdan: bakiyesiz tavan dolması 'Kapalı' diye yutulmuyor")
    func walletCappedWithoutBalance() {
        let state = WalletState(isEnabled: false, disabledReason: nil, consumedPercent: 100,
                                spendLimitReached: true, remainingBalance: 0)
        Self.turkish {
            let model = WalletPresentation.make(state, now: Self.now)
            #expect(model.status == "Tavan doldu")
            #expect(model.statusTone == .warn)
            #expect(model.help == "Aylık tavana ulaşıldığı için kullanım duraklatıldı.")
        }
    }

    // MARK: - Pencere

    private static func state(
        _ kind: WindowKind = .fiveHour,
        utilization: Int,
        start: Date?,
        reset: Date?,
        idle: Bool = false
    ) -> WindowState {
        WindowState(kind: kind, utilization: utilization, windowStart: start, resetAt: reset,
                    startUncertainty: 0, isIdle: idle, observedResets: [])
    }

    @Test("Pencere: başlamamış")
    func windowIdle() {
        Self.turkish {
            let got = WindowPresentation.make(
                state: Self.state(utilization: 0, start: nil, reset: nil, idle: true),
                projection: nil, samples: [], now: Self.now, server: nil)
            #expect(got == WindowPresentation(
                kind: .fiveHour, usedPercent: 0, projectedPercent: 0,
                windowStart: nil, resetAt: nil,
                resetBadge: "Henüz başlamadı", absoluteReset: nil,
                paceMultiplier: nil, projectionNote: nil,
                isFull: false, willOverrun: false, isAwaitingReset: false,
                history: [], forecast: [], isIdle: true))
        }
    }

    @Test("Pencere: sıfırlanma anı geçti, yenisi bekleniyor")
    func windowAwaiting() {
        let start = Self.now.addingTimeInterval(-6 * 3600)
        let reset = Self.now.addingTimeInterval(-3600)
        Self.turkish {
            let got = WindowPresentation.make(
                state: Self.state(utilization: 40, start: start, reset: reset),
                projection: nil, samples: [], now: Self.now, server: nil)
            #expect(got == WindowPresentation(
                kind: .fiveHour, usedPercent: 40, projectedPercent: 40,
                windowStart: start, resetAt: reset,
                resetBadge: "sıfırlanma bekleniyor", absoluteReset: "sıfırlanma bekleniyor",
                paceMultiplier: nil, projectionNote: nil,
                isFull: false, willOverrun: false, isAwaitingReset: true,
                history: [], forecast: [], isIdle: false))
        }
    }

    @Test("Pencere: geri sayım")
    func windowCountdown() {
        let start = Self.now.addingTimeInterval(-2 * 3600)
        // 10:00 UTC.
        let reset = Self.now.addingTimeInterval(3 * 3600 + 34 * 60)
        Self.turkish {
            let got = WindowPresentation.make(
                state: Self.state(utilization: 40, start: start, reset: reset),
                projection: nil, samples: [], now: Self.now, server: nil)
            #expect(got == WindowPresentation(
                kind: .fiveHour, usedPercent: 40, projectedPercent: 40,
                windowStart: start, resetAt: reset,
                resetBadge: "3 sa 34 dk sonra sıfırlanır", absoluteReset: "10:00da sıfırlanır",
                paceMultiplier: nil, projectionNote: nil,
                isFull: false, willOverrun: false, isAwaitingReset: false,
                history: [], forecast: [], isIdle: false))
        }
    }

    @Test("Pencere: sunucu yüzdeyi, başlangıcı ve sıfırlanmayı ezer")
    func windowServerOverride() {
        // 09:00 UTC; başlangıç 04:00.
        let serverReset = Self.now.addingTimeInterval(2 * 3600 + 34 * 60)
        Self.turkish {
            let got = WindowPresentation.make(
                state: Self.state(utilization: 10, start: Self.now.addingTimeInterval(-3600),
                                  reset: Self.now.addingTimeInterval(4 * 3600)),
                projection: nil, samples: [], now: Self.now,
                server: ServerUsage.Window(utilization: 47.5, resetsAt: serverReset))
            #expect(got == WindowPresentation(
                kind: .fiveHour, usedPercent: 47.5, projectedPercent: 47.5,
                windowStart: serverReset.addingTimeInterval(-5 * 3600), resetAt: serverReset,
                resetBadge: "2 sa 34 dk sonra sıfırlanır", absoluteReset: "09:00da sıfırlanır",
                paceMultiplier: nil, projectionNote: nil,
                isFull: false, willOverrun: false, isAwaitingReset: false,
                history: [], forecast: [], isIdle: false))
        }
    }

    @Test("Aşım notu yalnız dolmamış ve pencere içinde dolacaksa")
    func projectionNoteGating() {
        let start = Self.now.addingTimeInterval(-2 * 3600)
        let reset = Self.now.addingTimeInterval(3 * 3600)
        func projection(overrun: Bool) -> Projection {
            Projection(ratePerHour: 30, multiplier: 1.5, projectedUtilization: 150,
                       fillAt: Self.now.addingTimeInterval(3600), willOverrun: overrun, forecast: [])
        }
        func note(used: Int, overrun: Bool) -> ProjectionNote? {
            WindowPresentation.make(
                state: Self.state(utilization: used, start: start, reset: reset),
                projection: projection(overrun: overrun), samples: [], now: Self.now, server: nil
            ).projectionNote
        }
        Self.turkish {
            #expect(note(used: 60, overrun: true) != nil)
            #expect(note(used: 100, overrun: true) == nil)
            #expect(note(used: 60, overrun: false) == nil)
        }
    }

    @Test("Eksen: 5 saatlikte 5, haftalıkta 8 işaret")
    func axisLabelCounts() {
        Self.turkish {
            let five = WindowPresentation.make(
                state: Self.state(.fiveHour, utilization: 10,
                                  start: Self.now, reset: Self.now.addingTimeInterval(5 * 3600)),
                projection: nil, samples: [], now: Self.now, server: nil)
            let week = WindowPresentation.make(
                state: Self.state(.sevenDay, utilization: 10,
                                  start: Self.now, reset: Self.now.addingTimeInterval(7 * 24 * 3600)),
                projection: nil, samples: [], now: Self.now, server: nil)
            #expect(five.axisLabels.count == 5)
            #expect(week.axisLabels.count == 8)
        }
    }

    // MARK: - Menü çubuğu

    @Test("Menü çubuğu: init varsayılanları")
    func menuBarDefaults() {
        let snapshot = MenuBarSnapshot(hasData: true, usedPercent: 10, countdownText: "1:00", isStale: false)
        #expect(snapshot.weeklyPercent == 0)
        #expect(snapshot.serviceOK == true)
    }

    @Test("Menü çubuğu: geri sayım boşken sıfırlanma cümlesi okunmaz")
    func spokenSummaryWithoutCountdown() {
        let empty = MenuBarSnapshot(hasData: true, usedPercent: 10, countdownText: "", isStale: false)
        let timed = MenuBarSnapshot(hasData: true, usedPercent: 10, countdownText: "1:00", isStale: false)
        L.$languageOverride.withValue(.english) {
            #expect(!empty.spokenSummary.contains("Resets"))
            #expect(timed.spokenSummary.hasSuffix("Resets in 1:00."))
        }
        L.$languageOverride.withValue(.turkish) {
            #expect(!empty.spokenSummary.contains("sıfırlanır"))
            #expect(timed.spokenSummary.hasSuffix("1:00 sonra sıfırlanır."))
        }
    }

    // == yüzdeyi pilin çizdiği gibi YUVARLAYARAK karşılaştırıyor: 45,4 → 45,6
    // çizilen sayıyı değiştiriyor, yeniden çizim atlanmamalı.
    @Test("Menü çubuğu: eşitlik yuvarlanmış yüzdeye bakıyor")
    func menuBarEquality() {
        let a = MenuBarSnapshot(hasData: true, usedPercent: 45.2, countdownText: "1:00", isStale: false)
        let b = MenuBarSnapshot(hasData: true, usedPercent: 44.8, countdownText: "1:00", isStale: false)
        let c = MenuBarSnapshot(hasData: true, usedPercent: 45.2, countdownText: "0:59", isStale: false)
        let d = MenuBarSnapshot(hasData: true, usedPercent: 45.4, countdownText: "1:00", isStale: false)
        let e = MenuBarSnapshot(hasData: true, usedPercent: 45.6, countdownText: "1:00", isStale: false)
        #expect(a == b)
        #expect(a != c)
        #expect(d != e)
        #expect(d.remainingPercent != e.remainingPercent)
    }

    // MARK: - Cüzdan çözümü

    private static func account(hasExtraUsage: Bool, reason: String? = nil) -> Account {
        Account(displayName: nil, email: nil, planLabel: "Pro", subscriptionStart: nil,
                hasExtraUsage: hasExtraUsage, extraUsageDisabledReason: reason,
                profileFetchedAt: nil)
    }

    private static func serverWallet(_ extra: [String: Any]) throws -> ServerUsage.Wallet {
        try #require(ServerUsage(json: ["extra_usage": extra]).wallet)
    }

    @Test("Cüzdan çözümü: sunucu cüzdanı kazanır")
    func resolveServerWins() throws {
        let server = try Self.serverWallet(["is_enabled": true, "monthly_limit": 2000, "used_credits": 500])
        let balance = ClaudeWebClient.Balance(remaining: 12, autoReloadEnabled: true)
        let got = WalletState.resolve(server: server, balance: balance,
                                      account: Self.account(hasExtraUsage: false), liveExtraUsage: nil)
        #expect(got.isEnabled)
        #expect(got.disabledReason == nil)
        #expect(got.monthlyLimit == 20)
        #expect(got.usedCredits == 5)
        #expect(got.remainingBalance == 12)
        #expect(got.autoReloadEnabled)
    }

    @Test("Cüzdan çözümü: hesap yokken xu sinyali açık demek")
    func resolveNoAccountWithSignal() {
        let got = WalletState.resolve(server: nil, balance: nil, account: nil, liveExtraUsage: 40)
        #expect(got == WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 40))
    }

    @Test("Cüzdan çözümü: xu, hesaptaki kapalı bayrağını ezer")
    func resolveSignalOverridesAccountFlag() {
        let got = WalletState.resolve(server: nil, balance: nil,
                                      account: Self.account(hasExtraUsage: false, reason: "user_level_disabled"),
                                      liveExtraUsage: 10)
        #expect(got == WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 10))
    }

    @Test("Cüzdan çözümü: yalnızca önbellek bayrağı kesin sunulmuyor")
    func resolveCacheOnlyIsUncertain() {
        let on = WalletState.resolve(server: nil, balance: nil,
                                     account: Self.account(hasExtraUsage: true), liveExtraUsage: nil)
        #expect(on.fromCache)
        #expect(on.isEnabled)
        Self.turkish {
            let model = WalletPresentation.make(on, now: Self.now)
            #expect(model.statusTone == .muted)
            #expect(model.amounts == "önbellekten, eski olabilir")

            let off = WalletState.resolve(server: nil, balance: nil,
                                          account: Self.account(hasExtraUsage: false), liveExtraUsage: nil)
            #expect(off.fromCache)
            #expect(WalletPresentation.make(off, now: Self.now).help == WalletPresentation.cacheNote)
        }
    }

    @Test("Cüzdan çözümü: kapalı sunucu cüzdanı sebebi hesaptan alır, yoksa genel ifade")
    func resolveDisabledServerReason() throws {
        let server = try Self.serverWallet(["is_enabled": false])
        Self.turkish {
            let fromAccount = WalletState.resolve(
                server: server, balance: nil,
                account: Self.account(hasExtraUsage: false, reason: "not_eligible"), liveExtraUsage: nil)
            #expect(fromAccount.isEnabled == false)
            #expect(fromAccount.disabledReason == "bu plan için kullanılamıyor")

            let fallback = WalletState.resolve(server: server, balance: nil, account: nil, liveExtraUsage: nil)
            #expect(fallback.disabledReason == "ekstra kullanım kapalı")
        }
    }

    @Test("Menü çubuğu: 5 saatlik pencere yoksa veri yok")
    func menuBarWithoutFiveHour() {
        let got = MenuBarSnapshot.make(fiveHour: nil, weekly: nil, freshness: nil, serviceOK: false, now: Self.now)
        #expect(got.hasData == false)
        #expect(got.countdownText == "")
        #expect(got.serviceOK == false)
    }

    @Test("Menü çubuğu: sıfırlanma beklenirken geri sayım boş")
    func menuBarAwaitingReset() {
        let start = Self.now.addingTimeInterval(-6 * 3600)
        let reset = Self.now.addingTimeInterval(-3600)
        let window = WindowPresentation.make(
            state: Self.state(utilization: 40, start: start, reset: reset),
            projection: nil, samples: [], now: Self.now, server: nil)
        let got = MenuBarSnapshot.make(fiveHour: window, weekly: nil, freshness: nil, serviceOK: true, now: Self.now)
        #expect(got.hasData)
        #expect(got.usedPercent == 40)
        #expect(got.countdownText == "")
    }
}
