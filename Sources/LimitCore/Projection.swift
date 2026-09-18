import Foundation

/// Tahmin eğrisinin bir noktası: pencere içi konum (0-1) ve o noktada
/// öngörülen kullanım yüzdesi. Grafik bu noktaları çizgiyle birleştiriyor.
public struct ProjectionPoint: Sendable, Equatable {
    public let position: Double
    public let utilization: Double
    public init(position: Double, utilization: Double) {
        self.position = position
        self.utilization = utilization
    }
}

/// Bir pencerenin mevcut hızı ve bu hızın nereye gittiği.
///
/// TEK KURAL, iki pencerede de (kullanıcının formülü):
///
///     ideal kullanım   = geçen süre ÷ pencere süresi × %100
///     pace             = gerçek kullanım ÷ ideal kullanım
///     tahmini toplam   = geçen süre × (100 ÷ gerçek kullanım)
///
/// Örnek: 7 günlük pencerede 48. saatte ideal %28,57; gerçek %40 ise pace
/// 40 ÷ 28,57 = 1,40× ve bu hızla kota 48 × 100 ÷ 40 = 120. saatte biter.
///
/// Pace ile dolma anı aynı ortalama hızdan geliyor, dolayısıyla pace ≥ 1 ile
/// "sıfırlanmadan dolacak" her zaman birlikte doğru. Haftalık pencere için
/// eskiden geçmiş haftaların ritmini izleyen bir davranış eğrisi vardı; o eğri
/// bu formülden sapıyor ve pace ile tahmini birbirine düşürüyordu, kaldırıldı.
public struct Projection: Sendable, Equatable {
    /// Pencere başından bu yana ortalama tüketim hızı, yüzde/saat.
    public let ratePerHour: Double
    /// Arayüzdeki "1,40×": gerçek kullanım ÷ ideal kullanım.
    ///
    /// Hız ölçülemiyorsa (pencere çok genç) ya da pencere zaten dolmuşsa nil:
    /// arayüz o durumda hiçbir şey ya da "Doldu" yazıyor.
    public let multiplier: Double?
    /// Pencere sonunda ulaşılacak öngörülen yüzde. 100'ü aşabilir.
    public let projectedUtilization: Double
    /// %100'e ulaşılacak an.
    ///
    /// Pencerenin sıfırlanmasından sonrasına da düşebilir: o durumda limite
    /// çarpılmaz, ama "bu tempoyla ne zaman dolardı" sorusunun cevabı yine de
    /// anlamlıdır ve kullanıcıya ne kadar payı olduğunu gösterir.
    public let fillAt: Date?
    /// Dolma anı pencerenin sıfırlanmasından önce mi.
    public let willOverrun: Bool
    /// Gelecek için öngörülen eğri: ŞİMDİDEN pencere sonuna kadar düz çizgi.
    /// Grafikteki kesikli çizgi bunu çiziyor.
    public let forecast: [ProjectionPoint]
}

public struct Projector: Sendable {
    public init() {}

    public func project(_ state: WindowState, now: Date = Date()) -> Projection? {
        guard !state.isIdle, let resetAt = state.resetAt, let windowStart = state.windowStart else { return nil }

        let current = Double(state.utilization)
        let rate = averageRate(kind: state.kind, utilization: current, windowStart: windowStart, now: now)

        // Pencere DOLMUŞSA tahmin edilecek gelecek yok: eğri üretmek "%100'e
        // ne zaman varırsın" sorusunu zaten gerçekleşmiş bir olay için sormak
        // olur. Pace de yok: arayüz bu durumda "Doldu" yazıyor.
        guard current < 100 else {
            return Projection(
                ratePerHour: rate, multiplier: nil, projectedUtilization: current,
                fillAt: now, willOverrun: true, forecast: []
            )
        }

        let duration = resetAt.timeIntervalSince(windowStart)
        let elapsed = now.timeIntervalSince(windowStart)
        let hoursLeft = max(0, resetAt.timeIntervalSince(now)) / 3600
        let posNow = duration > 0 ? min(1, max(0, elapsed / duration)) : 0

        // Hız ölçülemiyorsa (bkz. `minimumRateSpan`) tahmin de pace de yok.
        guard rate > 0, duration > 0 else {
            return Projection(
                ratePerHour: rate, multiplier: nil, projectedUtilization: current,
                fillAt: nil, willOverrun: false, forecast: []
            )
        }

        // Kullanıcının formülü, doğrudan.
        let idealUsage = elapsed / duration * 100
        let pace = current / idealUsage
        let projected = current + rate * hoursLeft          // = pace × 100
        let fillAt = now.addingTimeInterval((100 - current) / rate * 3600)

        return Projection(
            ratePerHour: rate,
            multiplier: pace,
            projectedUtilization: projected,
            fillAt: fillAt,
            willOverrun: fillAt <= resetAt,
            forecast: [
                ProjectionPoint(position: posNow, utilization: current),
                ProjectionPoint(position: 1, utilization: projected),
            ]
        )
    }

    /// Bir hızın türetilebilmesi için gereken en kısa geçen süre.
    ///
    /// Formülün tek gerçek kırılma noktası paydanın sıfıra yaklaşması:
    /// pencerenin ilk dakikalarında `geçen` küçücükken oran uçuyor. Eşik
    /// bunu kapatacak kadar, tahmini gereksiz yere geciktirmeyecek kadar
    /// küçük: 5 saatlik pencerede 15 dakika, haftalıkta 1,7 saat.
    ///
    /// Daha önce eşik pencerenin yirmide biriydi (haftalıkta 8,4 saat) ve
    /// haftanın ilk gününde tahmini tümüyle susturuyordu. O ayar, "%668" gibi
    /// saçma sonuçlara karşı konmuştu; ama asıl sebep eşik değil paydaydı:
    /// geçen süre pencere başı yerine ilk kullanımdan ölçülüyordu. Payda
    /// düzelince o kadar geniş bir bariyere gerek kalmadı.
    static func minimumRateSpan(for kind: WindowKind) -> TimeInterval {
        max(15 * 60, kind.duration / 100)
    }

    /// Pencere başından bu yana ortalama tüketim hızı, yüzde/saat.
    ///
    /// Geçen süre yeterince uzun değilse hız üretilmiyor: tam sayı yüzdelerde
    /// kısa bir aralıktaki tek puanlık artış saatlik hıza çevrildiğinde uçuyor
    /// ve uzun pencerelerde saçma tahminler doğuruyor (23 dakikalık veriden
    /// yedi günlük pencere için "%668" gibi). Eşik pencere boyuyla ölçekli.
    func averageRate(
        kind: WindowKind, utilization: Double, windowStart: Date, now: Date
    ) -> Double {
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed >= Self.minimumRateSpan(for: kind), utilization > 0 else { return 0 }
        return utilization / (elapsed / 3600)
    }
}

/// Verinin ne kadar taze olduğu. Katman A yalnızca Claude Desktop açıkken güncellenir,
/// bu yüzden yaşlanma gizlenmez, gösterilir.
public enum Freshness: Sendable, Equatable {
    case live(Date)
    case aging(Date)
    case stale(Date)

    public init(lastUpdate: Date, now: Date = Date()) {
        let age = now.timeIntervalSince(lastUpdate)
        switch age {
        case ..<(10 * 60): self = .live(lastUpdate)
        case ..<(45 * 60): self = .aging(lastUpdate)
        default: self = .stale(lastUpdate)
        }
    }

    public var lastUpdate: Date {
        switch self {
        case .live(let d), .aging(let d), .stale(let d): d
        }
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
