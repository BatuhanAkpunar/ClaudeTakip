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
            windowStart: kind.windowStart(resettingAt: resetsAt),
            resetAt: resetsAt,
            startUncertainty: 0,
            isIdle: false,
            observedResets: []
        )
    }

    /// limitcheck tanılaması için
    public func timeRemaining(now: Date) -> TimeInterval? {
        guard let resetAt else { return nil }
        return max(0, resetAt.timeIntervalSince(now))
    }
}

extension WindowState {
    /// Projeksiyon için pencereyi sunucunun kesin sınırlarıyla düzeltir.
    ///
    /// Pencere ilk kullanımla başlıyor; bu doğru ve değişmiyor. Sorun ölçümde:
    /// yerel türetme "ilk kullanım"ı ancak yüzde ölçülebilir hale gelince
    /// görüyor. İlk mesajlar limitin binde birini harcadıysa yüzde bir süre 0
    /// kalıyor ve başlangıç saatlerce geç işaretleniyor. Gerçek örnek: sunucu
    /// pencerenin 09:59'da başladığını söylüyordu, yerel türetme 11:39 diyordu;
    /// 1 saat 40 dakikalık bu fark paydayı yarıya indirip hızı iki katına
    /// çıkarıyordu (pencere sonunda %23 yerine %43).
    ///
    /// `resets_at − pencere boyu` aynı anın kesin hâli, o yüzden varsa o
    /// kullanılıyor. Gösterimle hesap da böylece aynı pencereye bakıyor.
    public func corrected(by server: ServerUsage.Window?) -> WindowState {
        guard let resetsAt = server?.resetsAt else { return self }
        let utilization = Int(server?.utilization.rounded() ?? Double(self.utilization))
        return WindowState(
            kind: kind,
            utilization: utilization,
            windowStart: kind.windowStart(resettingAt: resetsAt),
            resetAt: resetsAt,
            startUncertainty: 0,
            isIdle: utilization <= 0,
            observedResets: observedResets
        )
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

        // Hangi düşüşün sıfırlanma sayıldığı tek yerde: bkz. `ResetRule`.
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
            // olduğundan çok daha erken başlatır, geçen süreyi şişirir ve
            // hem hızı hem tahmini aşağı çeker. Bilinen tek şey pencerenin
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
