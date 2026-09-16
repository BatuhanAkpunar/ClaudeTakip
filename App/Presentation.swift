import Foundation
import LimitCore

/// Ekstra kullanım cüzdanının durumu.
///
/// Cüzdan bir pencere değil bir bütçe: sıfırlanmıyor, tükeniyor. Ve
/// uygulamadaki tek para harcatan sayı olduğu için kapalıyken sessiz,
/// açıkken görünür, harcanırken diğer sayılardan daha yüksek sesli olmalı.
struct WalletState: Equatable {
    let isEnabled: Bool
    let disabledReason: String?
    /// Bütçenin harcanan payı. Yalnızca yerel veride bir ölçüm varsa dolu gelir.
    let consumedPercent: Double?
    /// Harcama tavanına ulaşıldığı için mi kapalı. "Kullanıcı kapattı"dan farklı:
    /// bu, çarpıp kesilmek demek.
    var spendLimitReached: Bool = false
    /// Aylık harcama tavanı ve harcanan tutar. Yalnızca sunucudan gelir.
    var monthlyLimit: Double? = nil
    var usedCredits: Double? = nil
    /// Kalan ön ödemeli bakiye. Ayrı bir uçtan geliyor, gelmeyebilir.
    var remainingBalance: Double? = nil
    /// Para birimi. Alanların tümü aynı birimde.
    var currency: String = "USD"
    /// Otomatik yükleme açık mı. Açıksa tavana çarpmak harcamayı DURDURMUYOR,
    /// bakiyeyi doldurup devam ettiriyor. Rakiplerin göstermediği, aslında en
    /// çok sürpriz üreten alan bu.
    var autoReloadEnabled: Bool = false
    /// Durum bilgisi canlı kaynaktan mı geliyor, yoksa eski bir profil
    /// önbelleğinden mi. İkincisinde kesin konuşulmuyor.
    let isFromStaleCache: Bool
    /// Önbellek eskiyse ne kadar eski olduğu.
    let cachedAt: Date?

    var statusText: String {
        if isFromStaleCache {
            return isEnabled ? L.t("Açık?", "On?") : L.t("Kapalı?", "Off?")
        }
        return isEnabled ? L.t("Açık", "On") : L.t("Kapalı", "Off")
    }

    /// Ön ödemeli bakiyenin sıfırlandığı an: her ayın biri, UTC.
    /// Anthropic faturalandırması UTC üzerinden ilerliyor.
    func resetsAt(now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth)
    }
}

/// Cüzdan kartının çözülmüş, kompakt hâli.
///
/// Tasarım kullanıcının verdiği minimal spec: açık/kapalı, harcanan + kalan
/// (toplamı limit), yenilenme tarihi, oto-yükleme. Büyük kahraman sayı yok;
/// durum başlığın karşısında (Fable'daki gibi), gerisi iki ince satır.
struct WalletPresentation: Equatable {
    enum Tone: Equatable { case calm, warn, danger, muted }

    /// Başlığın karşısındaki durum: "Açık" / "Kapalı".
    var status: String
    var statusTone: Tone = .muted
    /// Harcanan / toplam çubuğu. nil ise çizilmez.
    var barFraction: Double?
    var barTone: Tone = .calm
    /// Kahraman sayı: kartın cevapladığı tek soru "ne kadar param kaldı".
    /// Eskiden üç eşit 9 pt satır çiziliyordu ve "Kapalı" rozeti sayıdan
    /// büyüktü; kod yorumu kahraman diyordu, uygulama demiyordu.
    var heroValue: String?
    /// Kahraman sayının etiketi: "kalan" / "harcandı".
    var heroLabel: String?
    /// Kahramanın altındaki ikincil tutar: "$13,83 harcandı".
    var detail: String?
    /// Kahraman sayı yokken (kapalı sebebi, giriş çağrısı) tek satır metin.
    var amounts: String?
    /// Bakiyenin yenilenme tarihi ("1 Eyl"). Cümle değil yalnızca değer:
    /// yanındaki simge ne olduğunu zaten söylüyor.
    var renewalDate: String?
    /// Otomatik yükleme açık mı. nil ise satır hiç çizilmiyor.
    var autoReload: Bool?
    var help: String = ""

    private static func severity(_ f: Double) -> Tone {
        switch f {
        case ..<0.5: return .calm
        case ..<0.85: return .warn
        default: return .danger
        }
    }

    static func make(_ state: WalletState, now: Date = Date()) -> WalletPresentation {
        let c = state.currency
        func m(_ v: Double) -> String { Format.money(v, currency: c) }

        let spent = state.usedCredits
        let limit = state.monthlyLimit
        let balance = state.remainingBalance
        // Tasarımda yenilenme satırı tam cümle: "1 Ekimde sıfırlanır".
        let resetPart = state.resetsAt(now: now).map { Format.resetSentence($0, includeTime: false) }
        let autoPart = state.autoReloadEnabled


        // --- AÇIK ---
        if state.isEnabled {
            let capped = state.spendLimitReached
            // Para verisi var: harcanan + kalan.
            if spent != nil || balance != nil || limit != nil {
                // Toplam = kullanıcının modeli: harcanan + kalan. İkisi yoksa tavana düş.
                let total: Double? = (spent != nil && balance != nil)
                    ? spent! + balance! : limit
                let frac: Double? = {
                    if let spent, let total, total > 0 { return min(spent / total, 1) }
                    if let p = state.consumedPercent { return min(p / 100, 1) }
                    return nil
                }()
                // Kalan varsa kahraman o; yoksa harcanan. İkisi de varsa
                // harcanan detaya iniyor.
                let hero: (String, String?)? = {
                    // Etiket yok: kartın başlığı ve yanındaki "Kredi Kullanımı"
                    // satırı sayının ne olduğunu zaten söylüyor.
                    if let balance { return (m(balance), nil) }
                    if let spent { return (m(spent), L.t("harcandı", "spent")) }
                    return nil
                }()
                let detail: String? = (spent != nil && balance != nil)
                    ? L.t("\(m(spent!)) harcandı", "\(m(spent!)) spent") : nil
                return WalletPresentation(
                    status: capped ? L.t("Tavan doldu", "Limit reached") : L.t("Açık", "On"),
                    statusTone: capped ? .warn : .calm,
                    barFraction: frac,
                    barTone: capped ? .danger : severity(frac ?? 0),
                    heroValue: hero?.0,
                    heroLabel: hero?.1,
                    detail: detail,
                    renewalDate: resetPart,
                    autoReload: autoPart,
                    help: L.t(
                        "Ekstra kullanım açık. Harcanan ve kalan bakiye, toplamı bütçeni verir.",
                        "Extra usage is on. Spent plus remaining balance adds up to your budget."
                    )
                )
            }
            // Yalnız yüzde (yerel veri, giriş yok).
            if let p = state.consumedPercent {
                return WalletPresentation(
                    status: L.t("Açık", "On"), statusTone: .calm,
                    barFraction: min(p / 100, 1), barTone: severity(min(p / 100, 1)),
                    amounts: L.t("giriş yapınca tutarlar görünür", "sign in to see amounts"),
                    renewalDate: resetPart,
                    help: L.t(
                        "Yüzde yerel dosyadan geliyor. Tutarlar ve kalan bakiye için giriş gerekiyor.",
                        "The percentage comes from a local file. Sign in to see amounts and remaining balance."
                    )
                )
            }
            // Açık ama sayı yok.
            return WalletPresentation(
                status: L.t("Açık", "On"), statusTone: .calm, barFraction: nil,
                amounts: L.t("henüz harcama yok", "nothing spent yet"), renewalDate: resetPart,
                help: L.t(
                    "Ekstra kullanım açık. Tutarlar giriş yaptığında görünür.",
                    "Extra usage is on. Amounts appear once you sign in."
                )
            )
        }

        // --- KAPALI ---
        // Tavana çarparak kapanma ile kullanıcının kapatması farklı; ilkinde
        // durum amber.
        let capped = state.spendLimitReached
        if let balance, balance > 0 {
            return WalletPresentation(
                status: capped ? L.t("Tavan doldu", "Limit reached") : L.t("Kapalı", "Off"),
                statusTone: capped ? .warn : .muted,
                barFraction: nil,
                heroValue: m(balance),
                heroLabel: nil,
                renewalDate: resetPart,
                autoReload: autoPart,
                help: capped
                    ? L.t(
                        "Aylık tavana ulaşıldığı için kullanım duraklatıldı. Kalan \(m(balance)) bakiye, yeniden açılınca geçerli.",
                        "Usage is paused because the monthly limit was reached. The remaining \(m(balance)) stays available once it is turned back on."
                    )
                    : L.t(
                        "Ekstra kullanım kapalı, harcama olmuyor. Cüzdanda \(m(balance)) duruyor.",
                        "Extra usage is off, so nothing is being spent. \(m(balance)) is still in the wallet."
                    )
            )
        }
        return WalletPresentation(
            status: L.t("Kapalı", "Off"), statusTone: .muted, barFraction: nil,
            amounts: state.disabledReason ?? L.t("ekstra kullanım kapalı", "extra usage off"),
            help: L.t(
                "Ekstra kullanım kapalı. Abonelik limitin dolduğunda Claude durur, kredi harcanmaz.",
                "Extra usage is off. When your plan limit runs out Claude stops instead of spending credits."
            )
        )
    }
}

/// Kesikli projeksiyon çizgisinin ucundaki açıklama.
///
/// Koşullu göstermek yanıltıcıydı: 74 pt'lik bir çizimde %98 ile %100 arasında
/// 1,5 pt var, yani etiket olmadığında çizgi tepeye değmiş gibi görünüyor ama
/// aşım uyarısı çıkmıyordu. Çizginin ucu artık her durumda ne demek istediğini
/// yazıyor.
struct ProjectionNote: Equatable {
    let title: String
    let value: String
    /// Aşım öngörülüyorsa kırmızı, öngörülmüyorsa sakin renk.
    let isWarning: Bool
    /// Tahminin neye dayandığı. İki tahmin yöntemi çok farklı sonuç
    /// verebiliyor; hangisinin kullanıldığını gizlemek yerine söylüyoruz.
    let basis: String
}

struct SparkPoint: Equatable {
    /// Pencere içindeki konum, 0-1.
    let x: Double
    /// Kullanım yüzdesi, 0-100.
    let y: Double
}

/// Bir limit penceresinin arayüze hazır hali.
///
/// Görünümler `WindowState` ve `Projection` ile doğrudan uğraşmaz: biçimlendirme,
/// yüzde dönüşümleri ve metin üretimi burada bir kez yapılır.
struct WindowPresentation: Equatable {
    let kind: WindowKind
    let usedPercent: Double
    /// Pencerede geçen sürenin yüzdesi.
    let pacePercent: Double
    let projectedPercent: Double
    let windowStart: Date?
    let resetAt: Date?
    let resetBadge: String
    /// Başlığın yanında parantez içinde gösterilen mutlak sıfırlanma anı.
    let absoluteReset: String?
    let paceMultiplier: Double?
    /// Kesikli çizginin ucundaki açıklama. Aşım varsa saati, yoksa pencere
    /// sonunda ulaşılacak yüzdeyi söyler.
    let projectionNote: ProjectionNote?
    let isFull: Bool
    /// Tahmin, pencere KAPANMADAN önce %100'e varıyor mu. Grafikteki kesikli
    /// çizginin rengi buna bağlı: kırmızı bir uyarıdır, her tahmin uyarı değil.
    let willOverrun: Bool
    /// Türetilen sıfırlanma anı geçmişte kaldı ve yeni bir sıfırlanma henüz
    /// gözlenmedi. Pencere teorik olarak bitti ama kanıtı yok.
    let isAwaitingReset: Bool
    let history: [SparkPoint]
    /// Gelecek tahmin eğrisi (x: pencere konumu, y: kullanım%). Grafikteki
    /// kesikli çizgi bunu izliyor; haftalıkta davranış temelli, eğri.
    let forecast: [SparkPoint]
    let isIdle: Bool

    var paceMultiplierText: String? {
        paceMultiplier.map(Format.multiplier)
    }

    var title: String {
        switch kind {
        case .fiveHour: L.t("Mevcut Limit", "Current Limit")
        case .sevenDay: L.t("Haftalık Limit", "Weekly Limit")
        }
    }

    var icon: String {
        switch kind {
        case .fiveHour: "clock"
        case .sevenDay: "calendar"
        }
    }

    var accent: WindowAccent {
        switch kind {
        case .fiveHour: .fiveHour
        case .sevenDay: .sevenDay
        }
    }

    /// Grafiğin altındaki zaman ekseni. 5 saatlik pencerede saat, haftalıkta gün.
    ///
    /// Her iki pencerede de beş işaret var ve ikisi de pencereyi eşit
    /// aralıklara bölüyor. İlk işaret pencerenin başlangıcı, sonuncusu
    /// sıfırlanma anı: eksen tam olarak grafiğin gösterdiği aralığı kapsıyor,
    /// ne eksik ne fazla.
    ///
    /// İşaretler tam saatlere ya da gün başlarına denk gelmez (pencere
    /// 13:20'de başlarsa etiketler 13:20, 14:35, ... olur); amaç takvim
    /// sınırlarını göstermek değil, eğrinin altındaki zamanı okunur kılmak.
    var axisLabels: [String] {
        guard let start = windowStart, let end = resetAt else { return [] }
        let span = end.timeIntervalSince(start)

        // Haftalık pencerede 7 tık yerine 5 kullanmak matematiksel olarak
        // pencerenin tamamını kapsıyordu (ilk ve son tık start/end'e eşitti),
        // ama "29, 31, 1, 3, 5" gibi atlamalı günler "sadece 5 gün gösteriyor"
        // izlenimi veriyordu. 8 tık (0-7. gün) tam olarak bir hafta ve her
        // gün ayrı bir işaretle görünüyor.
        let count = kind == .fiveHour ? 5 : 8
        return (0..<count).map { step in
            let moment = start.addingTimeInterval(span * Double(step) / Double(count - 1))
            if kind == .fiveHour { return Format.hourLabel(moment) }

            // Uçlar tam tarih ("12 Eyl", "19 Eyl"), aradakiler kısa gün adı.
            // Tarih pencereyi konumlandırıyor, gün adları içindeki ritmi
            // okunur kılıyor. Pencere 480 pt'ye çıkınca sekiz işarete düşen
            // yuva 23,9 pt'den 36,8 pt'ye çıktı; "12 Eyl" 27,4 pt, artık
            // sığıyor (360 pt'de sığmadığı için gün numarasına inilmişti).
            if step == 0 || step == count - 1 { return Format.dayLabel(moment) }
            return Format.weekdayShort(moment)
        }
    }

    static func make(
        state: WindowState,
        projection: Projection?,
        samples: [QuotaSample],
        now: Date,
        server: ServerUsage.Window? = nil
    ) -> WindowPresentation {
        // Sunucu verisi varsa yüzde ve sıfırlanma anı türetilmiş değil kesin.
        // Pencere başlangıcı da sıfırlanmadan geriye sayılarak bulunuyor, bu
        // yerel gözlemden çıkarılan tahminden daha isabetli.
        let used = server?.utilization ?? Double(state.utilization)
        let resetAt = server?.resetsAt ?? state.resetAt
        let windowStart = server?.resetsAt.map { $0.addingTimeInterval(-state.kind.duration) }
            ?? state.windowStart

        var pace = 0.0
        var history: [SparkPoint] = []
        if let start = windowStart {
            let elapsed = now.timeIntervalSince(start)
            pace = min(100, max(0, elapsed / state.kind.duration * 100))

            history = samples
                .filter { $0.date >= start && $0.date <= now }
                .map { sample in
                    SparkPoint(
                        x: min(1, max(0, sample.date.timeIntervalSince(start) / state.kind.duration)),
                        y: Double(sample.utilization(state.kind))
                    )
                }
        }

        let isIdle = state.isIdle && server == nil
        // Sıfırlanma anı geçtiyse geri sayım anlamsız: "0 dk sonra sıfırlanır"
        // demek, geçmiş bir anı gelecekmiş gibi göstermek olur.
        let awaitingReset = !isIdle && (resetAt.map { $0 <= now } ?? false)

        var resetBadge = L.t("Henüz başlamadı", "Not started yet")
        if awaitingReset {
            resetBadge = L.t("sıfırlanma bekleniyor", "waiting for reset")
        } else if let resetAt, !isIdle {
            let left = Format.duration(max(0, resetAt.timeIntervalSince(now)))
            resetBadge = L.t("\(left) sonra sıfırlanır", "resets in \(left)")
        }

        // Limit zaten dolmuşsa tahmin edilecek bir şey kalmamıştır.
        // Halka sütunu dolmuş pencerede zaten "Doldu" diyor, grafikte tekrar yok.
        // 5 saatlik pencerede dolma anı her zaman birkaç saat içinde, tarih gürültü.
        var note: ProjectionNote?
        // Yalnızca GERÇEK aşımı göster: dolma anı pencerenin İÇİNDE ise.
        // Sıfırlanmadan sonraya düşen bir "aşım" aşım değil, tersine "bu pencere
        // dolmuyorsun" demek; onu göstermek yanıltıcıydı.
        if used < 100, let projection, projection.willOverrun, let fillAt = projection.fillAt {
            note = ProjectionNote(
                title: L.t("Tahmini Aşım", "Projected Overrun"),
                value: state.kind == .fiveHour ? Format.hourLabel(fillAt) : Format.stamp(fillAt),
                isWarning: true,
                basis: projection.usesHistory
                    ? L.t(
                        "Geçmiş haftalardaki kullanım alışkanlığına göre; hafta boyunca kullanımı nasıl dağıttığını dikkate alıyor.",
                        "Based on your usage habits in past weeks; it accounts for how you spread usage across the week."
                    )
                    : L.t(
                        "Günde 10 saat aktif kullanım varsayılarak; henüz alışkanlık çıkaracak kadar geçmiş yok.",
                        "Assuming 10 active hours per day; not enough history yet to model your habits."
                    )
            )
        }

        return WindowPresentation(
            kind: state.kind,
            usedPercent: used,
            pacePercent: pace,
            projectedPercent: projection?.projectedUtilization ?? used,
            windowStart: windowStart,
            resetAt: resetAt,
            resetBadge: resetBadge,
            // 5 saatlik pencere her zaman bugün ya da birkaç saat sonra bitiyor,
            // tarih yazmak gürültü. Haftalıkta tarih bilgi taşıyor.
            // Tasarımda bu alan kısaltma değil TAM CÜMLE: "19 Eylül 10:00da
            // sıfırlanır". 5 saatlik pencere her zaman bugün bittiği için
            // orada tarih yazılmıyor.
            absoluteReset: isIdle
                ? nil
                : (awaitingReset
                    ? L.t("sıfırlanma bekleniyor", "waiting to reset")
                    : resetAt.map { state.kind == .fiveHour
                        ? Format.resetSentenceTimeOnly($0)
                        : Format.resetSentence($0, includeTime: true) }),
            // Pace, 1'in altında da gösteriliyor: "ortalamanın yarısı hızla
            // gidiyorsun" en az "iki katı" kadar bilgi. Önceden hız sıfırken
            // gizleniyordu, ama duruş da bir durumdur.
            paceMultiplier: projection?.multiplier,
            projectionNote: note,
            isFull: used >= 100,
            willOverrun: projection?.willOverrun ?? false,
            isAwaitingReset: awaitingReset,
            history: history,
            forecast: (projection?.forecast ?? []).map {
                SparkPoint(x: $0.position, y: $0.utilization)
            },
            isIdle: isIdle
        )
    }
}

/// Menü çubuğu çiziminin tek girdisi. Aynı anahtar iki kez üretilirse yeniden çizilmez.
struct MenuBarSnapshot: Equatable {
    let hasData: Bool
    /// 5 saatlik pencerenin KULLANILAN yüzdesi.
    let usedPercent: Double
    /// Haftalık pencerenin kullanılan yüzdesi. Dış halka bunu gösteriyor.
    var weeklyPercent: Double = 0
    let countdownText: String
    /// Haftalık pencerenin kalan süresi ("6g 4s"). Menü çubuğunda SOLDA.
    var weeklyCountdownText: String = ""
    let isStale: Bool
    /// status.claude.com sağlıklı mı. Claude simgesinin rengi buna bağlı.
    var serviceOK: Bool = true
    var showPercent: Bool = true
    var showCountdown: Bool = true

    /// İç halkanın merkezinde yazan sayı: 5 saatlik limitin KALAN yüzdesi.
    /// Kullanıcının sorduğu soru "ne kadar hakkım kaldı", "ne kadar harcadım"
    /// değil; halkalar da aynı yönde okunuyor (dolu yay = kalan).
    var remainingPercent: Int { max(0, 100 - Int(usedPercent.rounded())) }

    /// Kullanıcı spec'i: ikon, yüzde ve kalan süre yan yana. İkisi de
    /// ayarlardan kapatılabilir, ikon her durumda kalır.
    /// Menü çubuğu yazısı artık YALNIZCA geri sayım. Yüzde pilin içine taşındı,
    /// yani ikon zaten söylüyor; yanına tekrar yazmak yer israfıydı.
    var title: String {
        guard hasData, showCountdown, !countdownText.isEmpty else { return "" }
        return countdownText
    }

    /// Genişlik kilidi için en geniş geri sayım. "4:28" biçiminde en geniş
    /// hâli iki hane saat + iki hane dakika.
    var widestPossibleTitle: String {
        showCountdown ? "0:00" : ""
    }

    var spokenSummary: String {
        guard hasData else { return L.t("Veri yok", "No data") }
        let weeklyLeft = max(0, 100 - Int(weeklyPercent.rounded()))
        return L.t(
            "Beş saatlik limitin yüzde \(remainingPercent) kaldı, "
                + "haftalık limitin yüzde \(weeklyLeft) kaldı. "
                + "\(countdownText) sonra sıfırlanır.",
            "\(remainingPercent) percent of your five-hour limit is left, "
                + "\(weeklyLeft) percent of your weekly limit is left. "
                + "Resets in \(countdownText)."
        )
    }

    static func == (lhs: MenuBarSnapshot, rhs: MenuBarSnapshot) -> Bool {
        lhs.hasData == rhs.hasData
            && Int(lhs.usedPercent) == Int(rhs.usedPercent)
            && Int(lhs.weeklyPercent) == Int(rhs.weeklyPercent)
            && lhs.countdownText == rhs.countdownText
            && lhs.isStale == rhs.isStale
            && lhs.serviceOK == rhs.serviceOK
            && lhs.showPercent == rhs.showPercent
            && lhs.showCountdown == rhs.showCountdown
    }
}
