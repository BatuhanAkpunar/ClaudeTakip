import Foundation

/// Bir limit penceresinin türetilmiş durumu.
public struct WindowState: Sendable, Equatable {
    public let kind: WindowKind
    /// Sunucudan gelen gerçek kullanım yüzdesi, 0-100.
    public let utilization: Int
    /// Pencerenin başladığı tahmini an. Dosyada yok, gözlemden türetilir.
    public let windowStart: Date?
    /// Pencerenin sıfırlanacağı tahmini an.
    public let resetAt: Date?
    /// `windowStart` tahmininin belirsizlik payı. Örnekleme aralığından gelir.
    public let startUncertainty: TimeInterval
    /// Kullanım henüz başlamadıysa pencere de başlamamıştır.
    public let isIdle: Bool
    /// Bu pencere için gözlemlenen sıfırlanma anları, en yeniden eskiye.
    public let observedResets: [Date]

    public init(
        kind: WindowKind,
        utilization: Int,
        windowStart: Date?,
        resetAt: Date?,
        startUncertainty: TimeInterval,
        isIdle: Bool,
        observedResets: [Date]
    ) {
        self.kind = kind
        self.utilization = utilization
        self.windowStart = windowStart
        self.resetAt = resetAt
        self.startUncertainty = startUncertainty
        self.isIdle = isIdle
        self.observedResets = observedResets
    }

    /// Yerel geçmiş olmadan, yalnızca sunucunun bildirdiği anlık değerden
    /// pencere kurar.
    ///
    /// Claude Desktop kurulu olmayan bir makinede türetilecek gözlem yok ama
    /// sunucu zaten kesin değeri veriyor: yüzde ve sıfırlanma anı biliniyor,
    /// pencere başlangıcı da sıfırlanmadan geriye sayılarak bulunuyor.
    public static func fromServer(
        kind: WindowKind,
        utilization: Double,
        resetsAt: Date
    ) -> WindowState {
        WindowState(
            kind: kind,
            utilization: Int(utilization.rounded()),
            windowStart: resetsAt.addingTimeInterval(-kind.duration),
            resetAt: resetsAt,
            startUncertainty: 0,
            isIdle: false,
            observedResets: []
        )
    }

    public func timeRemaining(now: Date) -> TimeInterval? {
        guard let resetAt else { return nil }
        return max(0, resetAt.timeIntervalSince(now))
    }
}

/// Kota örneklerinden pencere sınırlarını türetir.
///
/// `plan-usage-history.json` sıfırlanma zamanı içermez, yalnızca yüzde içerir.
/// Sıfırlanma anları yüzdenin düştüğü noktalardan okunur; pencere başlangıcı ise
/// kullanımın yeniden başladığı ilk örnekten kestirilir.
public struct WindowDeriver: Sendable {
    public init() {}

    public func derive(_ kind: WindowKind, from samples: [QuotaSample], now: Date = Date()) -> WindowState? {
        guard let latest = samples.last else { return nil }
        let values = samples.map { $0.utilization(kind) }

        // Yüzde bir pencere içinde birikimlidir, düşemez: düşüş sıfırlanmadır.
        //
        // Ama her düşüş değil. Artık tek bir seride üç kaynak karışabiliyor
        // (Claude Desktop dosyası, sunucu okuması, buluttan gelen ikinci cihaz)
        // ve bunların yuvarlaması ile gecikmesi farklı. Bir puanlık gerileme
        // sıfırlanma değil, kaynaklar arası gürültüdür; onu sıfırlanma saymak
        // pencereyi ortasından kesip hız hesabını da uçuruyordu.
        //
        // Gerçek sıfırlanma büyük ve aşağı doğrudur: ya değerin çoğu gider ya
        // da sıfıra yakın bir yere düşer.
        var resetIndices: [Int] = []
        for i in 1..<max(samples.count, 1) {
            let gap = samples[i].date.timeIntervalSince(samples[i - 1].date)
            if ResetRule.didReset(
                previous: values[i - 1], current: values[i],
                gap: gap, duration: kind.duration
            ) {
                resetIndices.append(i)
            }
        }

        let observedResets = resetIndices.reversed().map { samples[$0].date }

        // Mevcut pencere: son sıfırlanmadan bugüne kadarki dilim.
        let windowStartIndex = resetIndices.last ?? 0
        let slice = Array(samples[windowStartIndex...])

        // Pencere ancak ilk kullanımla başlar. Sıfırdaki örnekler henüz pencereye ait değildir.
        guard let firstActive = slice.firstIndex(where: { $0.utilization(kind) > 0 }) else {
            return WindowState(
                kind: kind,
                utilization: latest.utilization(kind),
                windowStart: nil,
                resetAt: nil,
                startUncertainty: 0,
                isIdle: true,
                observedResets: observedResets
            )
        }

        let activeSample = slice[firstActive]
        // Kullanım, önceki örnek ile ilk aktif örnek arasında bir noktada başladı.
        // Aralığın ortası alınır, belirsizlik payı aralığın yarısıdır.
        let previous: Date? = firstActive > 0
            ? slice[firstActive - 1].date
            : (windowStartIndex > 0 ? samples[windowStartIndex - 1].date : nil)

        let start: Date
        let uncertainty: TimeInterval
        if let previous, activeSample.date.timeIntervalSince(previous) <= kind.duration {
            // Önceki örnek AYNI pencereye ait olabilecek kadar yakın: kullanım
            // ikisinin arasında başladı, ortası en iyi kestirim.
            let gap = activeSample.date.timeIntervalSince(previous)
            start = previous.addingTimeInterval(gap / 2)
            uncertainty = gap / 2
        } else {
            // Boşluk pencere boyundan uzun: önceki örnek BAŞKA bir pencereye
            // ait ve aradaki sıfırlanma görülmedi. Ortasını almak pencereyi
            // olduğundan çok daha erken başlatıyor, geçen süreyi şişiriyor ve
            // hem hızı hem tahmini aşağı çekiyordu. Bilinen tek şey pencerenin
            // EN GEÇ bu örnekte başlamış olduğu.
            start = activeSample.date
            uncertainty = previous == nil ? 0 : kind.duration / 2
        }

        var resetAt = start.addingTimeInterval(kind.duration)

        // Haftalık pencere hesaba atanmış sabit bir saatte döner. Birden fazla
        // gözlem varsa tahmini son gözlemden zincirlemek, kestirimden daha isabetli.
        if kind == .sevenDay, let lastObserved = observedResets.first {
            resetAt = lastObserved.addingTimeInterval(kind.duration)
        }

        return WindowState(
            kind: kind,
            utilization: latest.utilization(kind),
            windowStart: start,
            resetAt: resetAt,
            startUncertainty: uncertainty,
            isIdle: false,
            observedResets: observedResets
        )
    }
}
