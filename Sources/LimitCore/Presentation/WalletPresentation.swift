import Foundation

/// Ekstra kullanım cüzdanının durumu.
///
/// Cüzdan bir pencere değil bir bütçe: sıfırlanmıyor, tükeniyor. Ve
/// uygulamadaki tek para harcatan sayı olduğu için kapalıyken sessiz,
/// açıkken görünür, harcanırken diğer sayılardan daha yüksek sesli olmalı.
public struct WalletState: Sendable, Equatable {
    public let isEnabled: Bool
    public let disabledReason: String?
    /// Bütçenin harcanan payı. Yalnızca yerel veride bir ölçüm varsa dolu gelir.
    public let consumedPercent: Double?
    /// Harcama tavanına ulaşıldığı için mi kapalı. "Kullanıcı kapattı"dan farklı:
    /// bu, çarpıp kesilmek demek.
    public var spendLimitReached: Bool = false
    /// Aylık harcama tavanı ve harcanan tutar. Yalnızca sunucudan gelir.
    public var monthlyLimit: Double? = nil
    public var usedCredits: Double? = nil
    /// Kalan ön ödemeli bakiye. Ayrı bir uçtan geliyor, gelmeyebilir.
    public var remainingBalance: Double? = nil
    /// Para birimi. Alanların tümü aynı birimde.
    public var currency: String = "USD"
    /// Otomatik yükleme açık mı. Açıksa tavana çarpmak harcamayı DURDURMUYOR,
    /// bakiyeyi doldurup devam ettiriyor. Rakiplerin göstermediği, aslında en
    /// çok sürpriz üreten alan bu.
    public var autoReloadEnabled: Bool = false
    /// Açık/kapalı yalnızca hesap dosyasının profil önbelleğinden mi geliyor.
    /// O önbellek saatlerce eskiyebildiği için durum KESİN sunulmamalı.
    public var fromCache: Bool = false

    public init(
        isEnabled: Bool,
        disabledReason: String?,
        consumedPercent: Double?,
        spendLimitReached: Bool = false,
        monthlyLimit: Double? = nil,
        usedCredits: Double? = nil,
        remainingBalance: Double? = nil,
        currency: String = "USD",
        autoReloadEnabled: Bool = false,
        fromCache: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.consumedPercent = consumedPercent
        self.spendLimitReached = spendLimitReached
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.remainingBalance = remainingBalance
        self.currency = currency
        self.autoReloadEnabled = autoReloadEnabled
        self.fromCache = fromCache
    }

    /// Ön ödemeli bakiyenin sıfırlandığı an: her ayın biri, UTC.
    /// Anthropic faturalandırması UTC üzerinden ilerliyor.
    static func balanceRenewal(after now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth)
    }
}

extension WalletState {
    /// Cüzdanın durumu.
    ///
    /// İki kaynak var ve tazelikleri çok farklı: hesap dosyasındaki
    /// `hasExtraUsageEnabled` bayrağı profil önbelleğinden geliyor ve saatlerce
    /// eskiyebiliyor, kota dosyasındaki `xu` alanı ise beş dakikada bir
    /// tazeleniyor. Bu yüzden canlı sinyal bayrağı eziyor: `xu` görünüyorsa
    /// cüzdan açıktır, bayrak ne derse desin.
    ///
    /// `balance`, `account` ve `liveExtraUsage` yalnızca ihtiyaç duyulan dalda
    /// okunuyor (autoclosure): store'un gözlenen özelliklerini okuyan bir
    /// görünüm, yalnızca gerçekten kullanılan kaynağa bağımlı kalsın.
    public static func resolve(
        server: ServerUsage.Wallet?,
        balance: @autoclosure () -> ClaudeWebClient.Balance?,
        account: @autoclosure () -> Account?,
        liveExtraUsage: @autoclosure () -> Int?
    ) -> WalletState {
        // Sunucu verisi varsa tartışma yok: bayrak da bakiye de oradan geliyor.
        if let server {
            return WalletState(
                isEnabled: server.isEnabled,
                // Sunucu kapalı diyorsa sebebi hesap dosyasında yazıyor olabilir;
                // orada da yoksa genel ifadeye düşülüyor.
                disabledReason: server.isEnabled
                    ? nil
                    : (account()?.extraUsageDisabledText ?? L.t("ekstra kullanım kapalı", "extra usage is off")),
                consumedPercent: server.utilization,
                spendLimitReached: server.spendLimitReached,
                monthlyLimit: server.monthlyLimit,
                usedCredits: server.usedCredits,
                remainingBalance: balance()?.remaining,
                currency: server.currency,
                autoReloadEnabled: balance()?.autoReloadEnabled ?? false
            )
        }

        let liveSignal = liveExtraUsage() != nil

        guard let account = account() else {
            return WalletState(
                isEnabled: liveSignal,
                disabledReason: nil,
                consumedPercent: liveExtraUsage().map(Double.init)
            )
        }

        let enabled = liveSignal || account.hasExtraUsage
        return WalletState(
            isEnabled: enabled,
            disabledReason: enabled ? nil : account.extraUsageDisabledText,
            consumedPercent: liveExtraUsage().map(Double.init),
            // Canlı sinyal yoksa karar yalnızca eskiyebilen bayraktan.
            fromCache: !liveSignal
        )
    }
}

/// Cüzdan kartının çözülmüş, kompakt hâli.
///
/// Tasarım kullanıcının verdiği minimal spec: açık/kapalı, harcanan + kalan
/// (toplamı limit), yenilenme tarihi, oto-yükleme. Kahraman sayı kalan bakiye;
/// durum başlığın karşısında (Fable'daki gibi).
public struct WalletPresentation: Sendable, Equatable {
    public enum Tone: Sendable, Equatable { case calm, warn, danger, muted }

    /// Başlığın karşısındaki durum: "Açık" / "Kapalı".
    public var status: String
    public var statusTone: Tone = .muted
    /// Harcanan / toplam çubuğu. nil ise çizilmez.
    public var barFraction: Double?
    public var barTone: Tone = .calm
    /// Kahraman sayı: kartın cevapladığı tek soru "ne kadar param kaldı".
    /// Kalan bakiye yoksa harcanan tutar.
    public var heroValue: String?
    /// Kahraman sayının etiketi: yalnızca harcanan gösterilirken "harcandı",
    /// kalan bakiyede yok.
    public var heroLabel: String?
    /// Kahramanın altındaki ikincil tutar: "$13,83 harcandı".
    public var detail: String?
    /// Kahraman sayı yokken (kapalı sebebi, giriş çağrısı) tek satır metin.
    public var amounts: String?
    /// Bakiyenin yenilenme cümlesi (`Format.resetSentence`, saatsiz): tarih
    /// dahil tam cümle.
    public var renewalDate: String?
    /// Otomatik yükleme açık mı. nil ise satır hiç çizilmiyor.
    public var autoReload: Bool?
    public var help: String = ""

    private static func severity(_ f: Double) -> Tone {
        switch f {
        case ..<0.5: return .calm
        case ..<0.85: return .warn
        default: return .danger
        }
    }

    /// Durum rozeti metinleri. `let` değil hesaplanan: dil her çağrıda yeniden okunuyor.
    public static var onText: String { L.t("Açık", "On") }
    public static var offText: String { L.t("Kapalı", "Off") }
    public static var limitReachedText: String { L.t("Tavan doldu", "Limit reached") }
    /// Durum profil önbelleğinden geldiğinde eklenen not.
    static var cacheNote: String {
        L.t("Durum Claude Desktop'ın önbelleğinden, eski olabilir. Giriş yapınca kesinleşir.",
            "Status comes from Claude Desktop's cache and may be out of date. Sign in to confirm.")
    }

    /// Tavana çarpmayı bilen iki dalın rozeti. Tavana çarparak kapanma ile
    /// kullanıcının kapatması farklı; ilkinde durum amber.
    private static func statusBadge(capped: Bool, enabled: Bool) -> (text: String, tone: Tone) {
        if capped { return (limitReachedText, .warn) }
        return enabled ? (onText, .calm) : (offText, .muted)
    }

    /// Tavanı bilmeyen dallar da aynı rozeti kullanıyor: tavana çarpma
    /// bilgisi yalnızca sunucudan geliyor ama geldiğinde hiçbir dal onu
    /// "Açık"/"Kapalı" diye yutmamalı.
    private static func stateBadge(_ state: WalletState) -> (text: String, tone: Tone) {
        statusBadge(capped: state.spendLimitReached, enabled: state.isEnabled)
    }

    public static func make(_ state: WalletState, now: Date = Date()) -> WalletPresentation {
        let currency = state.currency
        let money: (Double) -> String = { Format.money($0, currency: currency) }
        // Tasarımda yenilenme satırı tam cümle: "1 Ekimde sıfırlanır".
        let renewal = WalletState.balanceRenewal(after: now)
            .map { Format.resetSentence($0, includeTime: false) }
        return state.isEnabled
            ? enabled(state, renewal: renewal, money: money)
            : disabled(state, renewal: renewal, money: money)
    }

    // --- AÇIK ---
    private static func enabled(
        _ state: WalletState,
        renewal: String?,
        money: (Double) -> String
    ) -> WalletPresentation {
        let spent = state.usedCredits
        let balance = state.remainingBalance
        // Para verisi var: harcanan + kalan.
        if spent != nil || balance != nil || state.monthlyLimit != nil {
            // Harcanan ve kalan birlikte: toplam ikisinin toplamı, harcanan detaya iniyor.
            var pair: (spent: Double, balance: Double)?
            if let spent, let balance { pair = (spent, balance) }
            // Toplam = kullanıcının modeli: harcanan + kalan. İkisi yoksa tavana düş.
            let total: Double? = pair.map { $0.spent + $0.balance } ?? state.monthlyLimit
            let frac: Double?
            if let spent, let total, total > 0 {
                frac = min(spent / total, 1)
            } else if let p = state.consumedPercent {
                frac = min(p / 100, 1)
            } else {
                frac = nil
            }
            // Kalan varsa kahraman o; yoksa harcanan.
            // Etiket yok: kartın başlığı ve yanındaki "Kredi Kullanımı"
            // satırı sayının ne olduğunu zaten söylüyor.
            var heroValue: String?
            var heroLabel: String?
            if let balance {
                heroValue = money(balance)
            } else if let spent {
                heroValue = money(spent)
                heroLabel = L.t("harcandı", "spent")
            }
            var detail: String?
            if let pair {
                let spentText = money(pair.spent)
                detail = L.t("\(spentText) harcandı", "\(spentText) spent")
            }
            let badge = statusBadge(capped: state.spendLimitReached, enabled: true)
            return WalletPresentation(
                status: badge.text,
                statusTone: badge.tone,
                barFraction: frac,
                barTone: state.spendLimitReached ? .danger : severity(frac ?? 0),
                heroValue: heroValue,
                heroLabel: heroLabel,
                detail: detail,
                renewalDate: renewal,
                autoReload: state.autoReloadEnabled,
                help: L.t(
                    "Ekstra kullanım açık. Harcanan ve kalan bakiye, toplamı bütçeni verir.",
                    "Extra usage is on. Spent plus remaining balance adds up to your budget."
                )
            )
        }
        // Yalnız yüzde (yerel veri, giriş yok).
        if let p = state.consumedPercent {
            let badge = stateBadge(state)
            return WalletPresentation(
                status: badge.text, statusTone: badge.tone,
                barFraction: min(p / 100, 1), barTone: severity(min(p / 100, 1)),
                amounts: L.t("giriş yapınca tutarlar görünür", "sign in to see amounts"),
                renewalDate: renewal,
                help: L.t(
                    "Yüzde yerel dosyadan geliyor. Tutarlar ve kalan bakiye için giriş gerekiyor.",
                    "The percentage comes from a local file. Sign in to see amounts and remaining balance."
                )
            )
        }
        // Açık ama sayı yok.
        let badge = stateBadge(state)
        // Önbellekten gelen "açık" kesin değil: rozet sönük, "henüz harcama
        // yok" gibi bir iddia yerine belirsizlik yazıyor.
        if state.fromCache {
            return WalletPresentation(
                status: badge.text, statusTone: .muted, barFraction: nil,
                amounts: L.t("önbellekten, eski olabilir", "from cache, may be out of date"),
                renewalDate: renewal,
                help: cacheNote
            )
        }
        return WalletPresentation(
            status: badge.text, statusTone: badge.tone, barFraction: nil,
            amounts: L.t("henüz harcama yok", "nothing spent yet"), renewalDate: renewal,
            help: L.t(
                "Ekstra kullanım açık. Tutarlar giriş yaptığında görünür.",
                "Extra usage is on. Amounts appear once you sign in."
            )
        )
    }

    // --- KAPALI ---
    private static func disabled(
        _ state: WalletState,
        renewal: String?,
        money: (Double) -> String
    ) -> WalletPresentation {
        let capped = state.spendLimitReached
        if let balance = state.remainingBalance, balance > 0 {
            let badge = statusBadge(capped: capped, enabled: false)
            let balanceText = money(balance)
            return WalletPresentation(
                status: badge.text,
                statusTone: badge.tone,
                barFraction: nil,
                heroValue: balanceText,
                heroLabel: nil,
                renewalDate: renewal,
                autoReload: state.autoReloadEnabled,
                help: capped
                    ? L.t(
                        "Aylık tavana ulaşıldığı için kullanım duraklatıldı. Kalan \(balanceText) bakiye, yeniden açılınca geçerli.",
                        "Usage is paused because the monthly limit was reached. The remaining \(balanceText) stays available once it is turned back on."
                    )
                    : L.t(
                        "Ekstra kullanım kapalı, harcama olmuyor. Cüzdanda \(balanceText) duruyor.",
                        "Extra usage is off, so nothing is being spent. \(balanceText) is still in the wallet."
                    )
            )
        }
        let badge = statusBadge(capped: capped, enabled: false)
        return WalletPresentation(
            status: badge.text, statusTone: badge.tone, barFraction: nil,
            amounts: state.disabledReason ?? L.t("ekstra kullanım kapalı", "extra usage is off"),
            help: capped
                ? L.t(
                    "Aylık tavana ulaşıldığı için kullanım duraklatıldı.",
                    "Usage is paused because the monthly limit was reached."
                )
                : state.fromCache
                ? cacheNote
                : L.t(
                    "Ekstra kullanım kapalı. Abonelik limitin dolduğunda Claude durur, kredi harcanmaz.",
                    "Extra usage is off. When your plan limit runs out Claude stops instead of spending credits."
                )
        )
    }
}
