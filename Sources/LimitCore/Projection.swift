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
public struct Projection: Sendable, Equatable {
    /// Şu anki tüketim hızı, yüzde/saat.
    public let ratePerHour: Double
    /// Bu hızın, aynı pencere türündeki geçmiş ortalama hıza oranı. Arayüzdeki "1,3×".
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
    /// Gelecek için öngörülen eğri: ŞİMDİDEN pencere sonuna kadar. Grafikteki
    /// kesikli çizgi bunu çiziyor. Haftalıkta geçmiş davranış eğrisinden,
    /// 5 saatlikte doğrusal.
    public let forecast: [ProjectionPoint]
    /// Tahmin kullanıcının geçmiş HAFTALIK davranışına mı (true) yoksa daha
    /// basit doğrusal/aktif-saat modeline mi (false) dayanıyor.
    public let usesHistory: Bool
}

public struct Projector: Sendable {
    /// Karşılaştırma tabanı bu kadar geçmişten hesaplanır.
    public let baselineWindow: TimeInterval

    public init(baselineWindow: TimeInterval = 14 * 24 * 3600) {
        self.baselineWindow = baselineWindow
    }

    /// Aktif-saat modelinde günde kaç saat kullanım varsayılıyor.
    ///
    /// 7 günlük pencerede takvim saati (168) yanıltıcı: kimse haftanın her
    /// saatini kullanmıyor. Kullanıcının verdiği sabit; geçmiş yeterli değilken
    /// kullanılan basit modelin çekirdeği.
    static let activeHoursPerDay: Double = 10

    public func project(
        _ state: WindowState,
        samples: [QuotaSample],
        now: Date = Date()
    ) -> Projection? {
        guard !state.isIdle, let resetAt = state.resetAt, let windowStart = state.windowStart else { return nil }

        let kind = state.kind
        let current = Double(state.utilization)

        // Pace göstergesi (1,3×) her iki pencerede de anlık/ortalama hızın
        // geçmiş ortalamaya oranı; tahmin modelinden bağımsız.
        let rate = averageRate(kind: kind, utilization: current, windowStart: windowStart, now: now)
        let base = baselineRate(kind, samples: samples, now: now)
        let multiplier = base.map { $0 > 0 ? rate / $0 : nil } ?? nil

        // Pencere DOLMUŞSA tahmin edilecek gelecek yok: eğri üretmek "%100'e
        // ne zaman varırsın" sorusunu zaten gerçekleşmiş bir olay için sormak
        // olur. Boş eğri döndürmek grafiği de koruyor.
        guard current < 100 else {
            return Projection(
                ratePerHour: rate, multiplier: multiplier, projectedUtilization: current,
                fillAt: now, willOverrun: true, forecast: [], usesHistory: false
            )
        }

        // Haftalık pencerede tahmin DAVRANIŞ temelli: kullanıcının geçmiş
        // haftalarda kullanımı hafta boyunca nasıl dağıttığı öğreniliyor.
        // 5 saatlik pencere için doğrusal yeterli: pencere kısa, hafta-içi
        // ritim gibi bir desen barındırmıyor.
        let plan: ForecastPlan = kind == .sevenDay
            ? weeklyForecast(current: current, windowStart: windowStart, resetAt: resetAt,
                             samples: samples, now: now)
            : linearForecast(current: current, windowStart: windowStart, resetAt: resetAt, rate: rate, now: now)

        return Projection(
            ratePerHour: rate,
            multiplier: multiplier,
            projectedUtilization: plan.projected,
            fillAt: plan.fillAt,
            willOverrun: plan.fillAt.map { $0 <= resetAt } ?? false,
            forecast: plan.curve,
            usesHistory: plan.usesHistory
        )
    }

    private struct ForecastPlan {
        var projected: Double
        var fillAt: Date?
        var curve: [ProjectionPoint]
        var usesHistory: Bool
    }

    // MARK: - Doğrusal tahmin (5 saatlik + fallback)

    /// Mevcut ortalama hızın aynen sürdüğü varsayımı. Şimdiden pencere sonuna
    /// düz bir çizgi.
    private func linearForecast(
        current: Double, windowStart: Date, resetAt: Date, rate: Double, now: Date
    ) -> ForecastPlan {
        let hoursLeft = max(0, resetAt.timeIntervalSince(now)) / 3600
        let duration = resetAt.timeIntervalSince(windowStart)
        let posNow = min(1, max(0, now.timeIntervalSince(windowStart) / duration))

        let projected = current + rate * hoursLeft
        var fillAt: Date?
        if current >= 100 { fillAt = now }
        else if rate > 0 { fillAt = now.addingTimeInterval((100 - current) / rate * 3600) }

        var curve: [ProjectionPoint] = []
        if rate > 0 {
            curve = [ProjectionPoint(position: posNow, utilization: current),
                     ProjectionPoint(position: 1, utilization: projected)]
        }
        return ForecastPlan(projected: projected, fillAt: fillAt, curve: curve, usesHistory: false)
    }

    // MARK: - Davranış temelli haftalık tahmin

    /// Kullanıcının geçmiş haftalarda kullanımı hafta boyunca nasıl biriktirdiğine
    /// dayalı tahmin.
    ///
    /// Mantık: geçmiş her haftalık pencere için "zamanın %X'i geçtiğinde kullanım
    /// %Y'ydi" eğrisi çıkarılıyor, bunların ortalaması alınıyor. Bu ortalama eğri
    /// kullanıcının TİPİK haftalık ritmi (başı yavaş, ortası yoğun vb.). Mevcut
    /// hafta bu eğriye göre ölçekleniyor: şu an eğrinin öngördüğünden hızlıysa
    /// ölçek 1'in üstünde, gerisi de o oranda taşınıyor.
    ///
    /// Bu, "şu andan itibaren 7/24 aynı tempoda kullanırsan" senaryosundan çok
    /// daha gerçekçi: kullanıcı geceleri durup gündüz çalışıyorsa, ya da hafta
    /// sonu yavaşlıyorsa, ortalama eğri bunu zaten içeriyor.
    ///
    /// Yeterli geçmiş yoksa (2 tam haftadan az) aktif-saat modeline düşülüyor.
    private func weeklyForecast(
        current: Double, windowStart: Date, resetAt: Date, samples: [QuotaSample], now: Date
    ) -> ForecastPlan {
        let duration = resetAt.timeIntervalSince(windowStart)
        let posNow = min(1, max(0, now.timeIntervalSince(windowStart) / duration))

        let avg = averageWeeklyCurve(samples: samples, before: windowStart, duration: duration)
        let gNow = avg.map { curveValue($0, at: posNow) } ?? 0

        // Ölçek ancak eğri o noktada anlamlı bir değer verdiğinde güvenilir:
        // haftanın ilk saatlerinde ortalama kullanım sıfıra yakınken oran uçar.
        guard let avg, gNow >= 2, current > 0 else {
            return activeHourForecast(current: current, windowStart: windowStart, resetAt: resetAt, now: now)
        }

        // Ölçek makul aralığa kırpılıyor: bir hafta içinde ortalamanın dört
        // katından fazla sapma ya da dörtte birinden azı, tek bir haftalık
        // örnekten güvenle iddia edilemez.
        let scale = min(4, max(0.25, current / gNow))

        // Gelecek eğri: şimdiden pencere sonuna, ortalama eğri × ölçek.
        var curve: [ProjectionPoint] = []
        let steps = 24
        for i in 0...steps {
            let pos = posNow + (1 - posNow) * Double(i) / Double(steps)
            let value = min(100, max(current, curveValue(avg, at: pos) * scale))
            curve.append(ProjectionPoint(position: pos, utilization: value))
        }

        let projected = curveValue(avg, at: 1) * scale
        let fillAt = fillTime(curve: curve, windowStart: windowStart, duration: duration)

        return ForecastPlan(projected: projected, fillAt: fillAt, curve: curve, usesHistory: true)
    }

    /// "Günde 10 saat aktif" doğrusal model. Geçmiş yeterli değilken.
    ///
    /// Takvim saati yerine aktif saat sayılıyor: pencere başından şimdiye kadar
    /// geçen aktif saat üzerinden hız, kalan aktif saat üzerinden tahmin.
    private func activeHourForecast(
        current: Double, windowStart: Date, resetAt: Date, now: Date
    ) -> ForecastPlan {
        let duration = resetAt.timeIntervalSince(windowStart)
        let posNow = min(1, max(0, now.timeIntervalSince(windowStart) / duration))

        let elapsedActive = activeHours(from: windowStart, to: now)
        guard elapsedActive >= 1, current > 0 else {
            return ForecastPlan(projected: current, fillAt: nil, curve: [], usesHistory: false)
        }
        let ratePerActiveHour = current / elapsedActive

        var curve: [ProjectionPoint] = []
        let steps = 24
        for i in 0...steps {
            let pos = posNow + (1 - posNow) * Double(i) / Double(steps)
            let moment = windowStart.addingTimeInterval(pos * duration)
            let active = activeHours(from: windowStart, to: moment)
            let value = min(100, max(current, ratePerActiveHour * active))
            curve.append(ProjectionPoint(position: pos, utilization: value))
        }
        let projected = ratePerActiveHour * activeHours(from: windowStart, to: resetAt)
        let fillAt = fillTime(curve: curve, windowStart: windowStart, duration: duration)
        return ForecastPlan(projected: projected, fillAt: fillAt, curve: curve, usesHistory: false)
    }

    /// Pencere başından verilen ana kadar biriken AKTİF saat (günde 10 saat).
    ///
    /// Aktif dilim yerel günün ortasına yerleştiriliyor (09:00-19:00): tam gün
    /// sınırında değil, kabaca çalışma saatlerinde. Kesin saatler önemli değil,
    /// önemli olan takvim saati yerine sabit bir günlük bütçe kullanmak.
    func activeHours(from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dayStartHour = 9.0
        let span = Self.activeHoursPerDay

        var total = 0.0
        var dayCursor = calendar.startOfDay(for: start)
        while dayCursor < end {
            let activeStart = dayCursor.addingTimeInterval(dayStartHour * 3600)
            let activeEnd = activeStart.addingTimeInterval(span * 3600)
            let lo = max(activeStart, start)
            let hi = min(activeEnd, end)
            if hi > lo { total += hi.timeIntervalSince(lo) / 3600 }
            dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor) ?? end
        }
        return total
    }

    // MARK: - Geçmiş haftalık eğri

    /// Geçmiş haftalık pencerelerin ortalama birikim eğrisi.
    ///
    /// Her tamamlanmış pencere için (konum 0-1, kullanım%) noktaları çıkarılıp
    /// 0..1 ızgarasında örnekleniyor ve ortalanıyor. En az iki tam pencere yoksa
    /// nil dönüyor.
    func averageWeeklyCurve(
        samples: [QuotaSample], before windowStart: Date, duration: TimeInterval
    ) -> [ProjectionPoint]? {
        let past = samples.filter { $0.date < windowStart }
        guard past.count > 10 else { return nil }

        // Sıfırlanmalardan pencerelere böl (WindowDeriver ile aynı eşik).
        var resetIndices: [Int] = [0]
        for i in 1..<past.count {
            let gap = past[i].date.timeIntervalSince(past[i - 1].date)
            if ResetRule.didReset(
                previous: past[i - 1].sevenDay, current: past[i].sevenDay,
                gap: gap, duration: duration
            ) {
                resetIndices.append(i)
            }
        }
        guard resetIndices.count >= 3 else { return nil }  // en az 2 tam pencere

        // Her tam pencerenin eğrisi.
        var curves: [[ProjectionPoint]] = []
        for k in 0..<(resetIndices.count - 1) {
            let slice = Array(past[resetIndices[k]..<resetIndices[k + 1]])
            guard slice.count > 5, let t0 = slice.first?.date else { continue }
            let points = slice.compactMap { sample -> ProjectionPoint? in
                let pos = sample.date.timeIntervalSince(t0) / duration
                guard pos >= 0, pos <= 1 else { return nil }
                return ProjectionPoint(position: pos, utilization: Double(sample.sevenDay))
            }
            // Yalnızca gerçekten kullanılmış, tamamlanmaya yakın pencereler:
            // yarıda bırakılmış bir hafta ortalamayı aşağı çekerdi.
            if let last = points.last, last.utilization >= 50 { curves.append(points) }
        }
        guard curves.count >= 2 else { return nil }

        // 0..1'i 20 noktada örnekle, ortala.
        let grid = 20
        return (0...grid).map { i -> ProjectionPoint in
            let pos = Double(i) / Double(grid)
            let mean = curves.map { curveValue($0, at: pos) }.reduce(0, +) / Double(curves.count)
            return ProjectionPoint(position: pos, utilization: mean)
        }
    }

    /// Bir eğriyi verilen konumda doğrusal ara-değerle değerlendirir.
    func curveValue(_ curve: [ProjectionPoint], at pos: Double) -> Double {
        guard let first = curve.first, let last = curve.last else { return 0 }
        if pos <= first.position { return first.utilization }
        if pos >= last.position { return last.utilization }
        for i in 1..<curve.count where curve[i].position >= pos {
            let a = curve[i - 1], b = curve[i]
            let span = b.position - a.position
            guard span > 0 else { return a.utilization }
            return a.utilization + (b.utilization - a.utilization) * (pos - a.position) / span
        }
        return last.utilization
    }

    /// Bir tahmin eğrisinin ilk kez %100'e ulaştığı an.
    private func fillTime(curve: [ProjectionPoint], windowStart: Date, duration: TimeInterval) -> Date? {
        for i in 1..<max(curve.count, 1) where curve[i].utilization >= 100 {
            let a = curve[i - 1], b = curve[i]
            let span = b.utilization - a.utilization
            let frac = span > 0 ? (100 - a.utilization) / span : 0
            let pos = a.position + (b.position - a.position) * frac
            return windowStart.addingTimeInterval(pos * duration)
        }
        return nil
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

    /// Geçmişteki ortalama tüketim hızı: gözlenen zamana bölünmüş toplam tüketim.
    ///
    /// Eskiden payda yalnızca "artışın görüldüğü" aralıkları topluyordu. Yüzde
    /// tam sayı olduğu için sık örneklemede aralıkların çoğunda artış 0 çıkıyor,
    /// payda da "bir puanlık tikin düştüğü aralıklar"a iniyordu. Sonuç: taban
    /// ≈ 1 puan / örnekleme aralığı. Aynı gerçek hız, bir dakikalık örneklemede
    /// saatte 60, on dakikalıkta saatte 5,8 puan ölçülüyordu; iki cihazın
    /// örnekleri buluttan birleşince taban kendiliğinden iki katına çıkıyordu.
    ///
    /// Artık pay da payda da koşulsuz: duraklamalar ikisine de dahil. Böylece
    /// taban örnekleme sıklığından bağımsız ve anlık hızla aynı türden bir
    /// büyüklük, yani oranları karşılaştırılabilir.
    func baselineRate(_ kind: WindowKind, samples: [QuotaSample], now: Date) -> Double? {
        let cutoff = now.addingTimeInterval(-baselineWindow)
        let recent = samples.filter { $0.date >= cutoff }
        guard recent.count > 2 else { return nil }

        var accumulated = 0.0
        var observedHours = 0.0
        for i in 1..<recent.count {
            let hours = recent[i].date.timeIntervalSince(recent[i - 1].date) / 3600
            // Uzun boşluklar gerçek çalışma değil, uygulamanın kapalı olduğu zaman.
            guard hours > 0, hours <= 1 else { continue }
            observedHours += hours
            let delta = Double(recent[i].utilization(kind) - recent[i - 1].utilization(kind))
            guard delta > 0 else { continue }  // sıfırlanma veya duruş
            accumulated += delta
        }
        // İki saatten az gözlemle bölme kararsız: tek bir puanlık tik tabanı
        // uçurup pace'i anlamsız kılıyordu.
        guard observedHours >= 2 else { return nil }
        return accumulated / observedHours
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
