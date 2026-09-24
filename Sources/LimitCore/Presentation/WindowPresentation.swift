import Foundation

/// Kesikli projeksiyon çizgisinin ucundaki açıklama.
///
/// Yalnızca gerçek aşımda çıkar: tahmini dolma anı pencerenin İÇİNDE ve
/// limit henüz dolmamışsa. Pencere sonrasına düşen dolma aşım değildir.
public struct ProjectionNote: Sendable, Equatable {
    public let title: String
    public let value: String
    /// Tahminin neye dayandığı. İki tahmin yöntemi çok farklı sonuç
    /// verebiliyor; hangisinin kullanıldığını gizlemek yerine söylüyoruz.
    public let basis: String
}

public struct SparkPoint: Sendable, Equatable {
    /// Pencere içindeki konum, 0-1.
    public let x: Double
    /// Kullanım yüzdesi, 0-100.
    public let y: Double
}

/// Bir limit penceresinin arayüze hazır hali.
///
/// Görünümler `WindowState` ve `Projection` ile doğrudan uğraşmaz: biçimlendirme,
/// yüzde dönüşümleri ve metin üretimi burada bir kez yapılır.
public struct WindowPresentation: Sendable, Equatable {
    public let kind: WindowKind
    public let usedPercent: Double
    public let projectedPercent: Double
    public let windowStart: Date?
    public let resetAt: Date?
    public let resetBadge: String
    /// Başlığın yanında parantez içinde gösterilen mutlak sıfırlanma anı.
    public let absoluteReset: String?
    public let paceMultiplier: Double?
    /// Kesikli çizginin ucundaki açıklama: öngörülen aşımın saati. Aşım
    /// yoksa nil.
    public let projectionNote: ProjectionNote?
    public let isFull: Bool
    /// Tahmin, pencere KAPANMADAN önce %100'e varıyor mu. Grafikteki kesikli
    /// çizginin rengi buna bağlı: kırmızı bir uyarıdır, her tahmin uyarı değil.
    public let willOverrun: Bool
    /// Türetilen sıfırlanma anı geçmişte kaldı ve yeni bir sıfırlanma henüz
    /// gözlenmedi. Pencere teorik olarak bitti ama kanıtı yok.
    public let isAwaitingReset: Bool
    public let history: [SparkPoint]
    /// Gelecek tahmin eğrisi (x: pencere konumu, y: kullanım%). Grafikteki
    /// kesikli çizgi bunu izliyor: şimdiden pencere sonuna düz çizgi.
    public let forecast: [SparkPoint]
    public let isIdle: Bool

    /// Grafiğin altındaki zaman ekseni. 5 saatlik pencerede saat, haftalıkta gün.
    ///
    /// 5 saatlik pencerede beş, haftalıkta sekiz işaret var ve ikisi de
    /// pencereyi eşit aralıklara bölüyor. İlk işaret pencerenin başlangıcı, sonuncusu
    /// sıfırlanma anı: eksen tam olarak grafiğin gösterdiği aralığı kapsıyor,
    /// ne eksik ne fazla.
    ///
    /// İşaretler tam saatlere ya da gün başlarına denk gelmez (pencere
    /// 13:20'de başlarsa etiketler 13:20, 14:35, ... olur); amaç takvim
    /// sınırlarını göstermek değil, eğrinin altındaki zamanı okunur kılmak.
    public var axisLabels: [String] {
        guard let start = windowStart, let end = resetAt else { return [] }
        let span = end.timeIntervalSince(start)

        let count = kind.axisTickCount
        return (0..<count).map { step in
            let moment = start.addingTimeInterval(span * Double(step) / Double(count - 1))
            if kind == .fiveHour { return Format.hourLabel(moment) }

            // Uçlar tam tarih ("12 Eyl", "19 Eyl"), aradakiler kısa gün adı.
            // Tarih pencereyi konumlandırıyor, gün adları içindeki ritmi
            // okunur kılıyor. 480 pt pencerede sekiz işarete düşen yuva
            // 36,8 pt; "12 Eyl" 27,4 pt olduğu için sığıyor (360 pt'de yuva
            // 23,9 pt olur ve sığmaz).
            if step == 0 || step == count - 1 { return Format.shortDate(moment) }
            return Format.weekdayShort(moment)
        }
    }

    public static func make(
        state: WindowState,
        projection: Projection?,
        samples: [QuotaSample],
        now: Date,
        server: ServerUsage.Window?
    ) -> WindowPresentation {
        // Sunucu verisi varsa yüzde ve sıfırlanma anı türetilmiş değil kesin.
        // Pencere başlangıcı da sıfırlanmadan geriye sayılarak bulunuyor, bu
        // yerel gözlemden çıkarılan tahminden daha isabetli.
        let used = server?.utilization ?? Double(state.utilization)
        let resetAt = server?.resetsAt ?? state.resetAt
        let windowStart = server?.resetsAt.map(state.kind.windowStart(resettingAt:))
            ?? state.windowStart

        var history: [SparkPoint] = []
        if let start = windowStart {
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
        let phase = ResetPhase(isIdle: isIdle, resetAt: resetAt, now: now)
        let resetBadge: String
        // 5 saatlik pencere her zaman bugün ya da birkaç saat sonra bitiyor,
        // tarih yazmak gürültü. Haftalıkta tarih bilgi taşıyor.
        // Tasarımda bu alan kısaltma değil TAM CÜMLE: "19 Eylül 10:00da
        // sıfırlanır". 5 saatlik pencere her zaman bugün bittiği için
        // orada tarih yazılmıyor.
        let absoluteReset: String?
        switch phase {
        case .notStarted:
            resetBadge = L.t("Henüz başlamadı", "Not started yet")
            absoluteReset = nil
        case .awaiting:
            // Rozet ve başlık yanındaki cümle aynı ifade: Türkçede zaten
            // aynıydı, İngilizcede iki farklı kalıp tutarsız okunuyordu.
            resetBadge = L.t("sıfırlanma bekleniyor", "waiting for reset")
            absoluteReset = resetBadge
        case .upcoming(let resetAt):
            // Format.duration negatifi sıfıra kırpıyor.
            let left = Format.duration(resetAt.timeIntervalSince(now))
            resetBadge = L.t("\(left) sonra sıfırlanır", "resets in \(left)")
            absoluteReset = state.kind.resetSentence(resetAt)
        }
        let awaitingReset = phase.isAwaiting

        // Limit zaten dolmuşsa tahmin edilecek bir şey kalmamıştır.
        // Halka sütunu dolmuş pencerede zaten "Doldu" diyor, grafikte tekrar yok.
        // 5 saatlik pencerede dolma anı her zaman birkaç saat içinde, tarih gürültü.
        var note: ProjectionNote?
        // Yalnızca GERÇEK aşımı göster: dolma anı pencerenin İÇİNDE ise.
        // Sıfırlanmadan sonraya düşen bir "aşım" aşım değil, tersine "bu pencere
        // dolmuyorsun" demek; onu göstermek yanıltıcı olur.
        if used < 100, let projection, projection.willOverrun, let fillAt = projection.fillAt {
            note = ProjectionNote(
                title: L.t("Tahmini Aşım", "Projected Overrun"),
                value: state.kind.instantLabel(fillAt),
                basis: L.t(
                    "Şu ana kadarki ortalama hızla devam edersen: geçen süre × 100 ÷ kullanım.",
                    "If you keep your average pace so far: elapsed time × 100 ÷ usage."
                )
            )
        }

        return WindowPresentation(
            kind: state.kind,
            usedPercent: used,
            projectedPercent: projection?.projectedUtilization ?? used,
            windowStart: windowStart,
            resetAt: resetAt,
            resetBadge: resetBadge,
            absoluteReset: absoluteReset,
            // Pace = pencere sonunda öngörülen kullanım ÷ kota; tahminle aynı
            // modelden, yani 1'in üstü ile "Tahmini Aşım" her zaman birlikte.
            // 1'in altında da gösteriliyor: "sıfırlanmada kotanın 0,6'sı" en az
            // "1,3'ü" kadar bilgi.
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

    /// Sıfırlanmaya kalan süre; pencere başlamadıysa ya da an bilinmiyorsa 0.
    public func remaining(at now: Date) -> TimeInterval {
        guard !isIdle, let resetAt else { return 0 }
        return max(0, resetAt.timeIntervalSince(now))
    }
}

/// Limit kartını süren üç sıfırlanma hâli.
private enum ResetPhase {
    /// Pencere başlamadı ya da sıfırlanma anı bilinmiyor.
    case notStarted
    /// Sıfırlanma anı geçmişte kaldı, yenisi henüz gözlenmedi.
    case awaiting
    case upcoming(Date)

    init(isIdle: Bool, resetAt: Date?, now: Date) {
        guard !isIdle, let resetAt else { self = .notStarted; return }
        // Sıfırlanma anı geçtiyse geri sayım anlamsız: "0 dk sonra sıfırlanır"
        // demek, geçmiş bir anı gelecekmiş gibi göstermek olur.
        self = resetAt <= now ? .awaiting : .upcoming(resetAt)
    }

    var isAwaiting: Bool {
        if case .awaiting = self { return true }
        return false
    }
}

/// 5 saatlik ile haftalık pencere arasındaki sunum farkları.
private extension WindowKind {
    /// Eksendeki işaret sayısı.
    ///
    /// Haftalıkta 8 işaret (0-7. gün): haftanın her günü ayrı bir işaret alıyor.
    /// 5 işaret "29, 31, 1, 3, 5" gibi atlamalı günler verir ve "sadece 5 gün
    /// gösteriyor" izlenimi uyandırır.
    var axisTickCount: Int {
        switch self {
        case .fiveHour: 5
        case .sevenDay: 8
        }
    }

    /// Tek bir anın etiketi (öngörülen aşım). 5 saatlik pencerede dolma anı
    /// her zaman birkaç saat içinde, tarih gürültü.
    func instantLabel(_ date: Date) -> String {
        switch self {
        case .fiveHour: Format.hourLabel(date)
        case .sevenDay: Format.stamp(date)
        }
    }

    /// Başlığın yanındaki sıfırlanma cümlesi: 5 saatlikte yalnız saat.
    func resetSentence(_ date: Date) -> String {
        switch self {
        case .fiveHour: Format.resetSentenceTimeOnly(date)
        case .sevenDay: Format.resetSentence(date, includeTime: true)
        }
    }
}
