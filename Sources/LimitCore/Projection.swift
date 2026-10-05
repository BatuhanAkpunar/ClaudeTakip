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

/// Pencere sonundaki tüketim ve %100'e ulaşma tahmini.
/// 5 saatlikte geçen sürenin ortalaması; haftalıkta yeterli geçmiş varsa
/// saatlik tüketim deseni. Pace her iki modelde de tahmini toplam / 100.
public struct Projection: Sendable, Equatable {
    /// Tahminin takvim saati başına tüketimi (haftalıkta kalan bölümün ortalaması).
    public let ratePerHour: Double
    /// Arayüzdeki "1,40×": pencere sonunda öngörülen kullanım ÷ 100.
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
    /// Gelecek için öngörülen eğri: şimdiden pencere sonuna kadar.
    /// Grafikteki kesikli çizgi bunu çiziyor.
    public let forecast: [ProjectionPoint]
    public var usesActivityPattern: Bool = false
}

public struct Projector: Sendable {
    public init() {}

    public func project(
        _ state: WindowState, now: Date = Date(), profile: UsageProfile? = nil,
        blockedUntil: Date? = nil, calendar: Calendar = .current
    ) -> Projection? {
        guard !state.isIdle, let resetAt = state.resetAt, let windowStart = state.windowStart,
              windowStart <= now, now < resetAt else { return nil }

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

        if state.kind == .sevenDay {
            return weeklyProjection(state, now: now, profile: profile,
                                    blockedUntil: blockedUntil, calendar: calendar)
        }

        // 5 saatlik pencere: geçen sürenin ortalaması.
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

    /// Haftalıkta en az bir gündüz/gece döngüsü bekle. İlk birkaç saatlik
    /// yoğun çalışmayı bütün haftaya yaymak aşırı erken aşım üretir.
    static func minimumRateSpan(for kind: WindowKind) -> TimeInterval {
        kind == .sevenDay ? 24 * 3600 : 15 * 60
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
