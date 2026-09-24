import Foundation

/// Menü çubuğu çiziminin tek girdisi. Aynı anahtar iki kez üretilirse yeniden çizilmez.
public struct MenuBarSnapshot: Sendable, Equatable {
    public let hasData: Bool
    /// 5 saatlik pencerenin KULLANILAN yüzdesi.
    public let usedPercent: Double
    /// Haftalık pencerenin kullanılan yüzdesi. Menü çubuğunda çizilmiyor;
    /// erişilebilirlik özeti okuyor.
    public var weeklyPercent: Double = 0
    public let countdownText: String
    public let isStale: Bool
    /// status.claude.com sağlıklı mı. Claude simgesinin rengi buna bağlı.
    public var serviceOK: Bool = true

    public init(
        hasData: Bool,
        usedPercent: Double,
        weeklyPercent: Double = 0,
        countdownText: String,
        isStale: Bool,
        serviceOK: Bool = true
    ) {
        self.hasData = hasData
        self.usedPercent = usedPercent
        self.weeklyPercent = weeklyPercent
        self.countdownText = countdownText
        self.isStale = isStale
        self.serviceOK = serviceOK
    }

    /// Pilin içinde yazan sayı: 5 saatlik limitin KALAN yüzdesi.
    /// Kullanıcının sorduğu soru "ne kadar hakkım kaldı", "ne kadar harcadım"
    /// değil; pil de aynı yönde okunuyor (dolu kısım = kalan).
    public var remainingPercent: Int { max(0, 100 - Int(usedPercent.rounded())) }

    public var spokenSummary: String {
        guard hasData else { return L.t("Veri yok", "No data") }
        let weeklyLeft = max(0, 100 - Int(weeklyPercent.rounded()))
        let limits = L.t(
            "Beş saatlik limitin yüzde \(remainingPercent) kaldı, "
                + "haftalık limitin yüzde \(weeklyLeft) kaldı.",
            "\(remainingPercent) percent of your five-hour limit is left, "
                + "\(weeklyLeft) percent of your weekly limit is left."
        )
        // Sıfırlanma beklenirken geri sayım boş: "Resets in ." okunmasın.
        guard !countdownText.isEmpty else { return limits }
        return limits + " " + L.t("\(countdownText) sonra sıfırlanır.", "Resets in \(countdownText).")
    }

    /// Menü çubuğu 5 saatlik pencereyi gösterir.
    ///
    /// Kullanıcı spec'i §2 net: menü çubuğunda haftalık kullanım gösterilmez,
    /// oraya yalnızca anlık durum ve kalan süre çıkar.
    public static func make(
        fiveHour: WindowPresentation?,
        weekly: WindowPresentation?,
        freshness: Freshness?,
        serviceOK: Bool,
        now: Date
    ) -> MenuBarSnapshot {
        let isStale = freshness?.isStale ?? false

        guard let window = fiveHour else {
            return MenuBarSnapshot(
                hasData: false, usedPercent: 0, countdownText: "", isStale: isStale,
                serviceOK: serviceOK
            )
        }

        return MenuBarSnapshot(
            hasData: true,
            usedPercent: window.usedPercent,
            weeklyPercent: weekly?.usedPercent ?? 0,
            // Sıfırlanma beklenirken geri sayım "0d" olurdu; yanlış bilgi
            // vermektense o alan boş bırakılıyor.
            countdownText: window.isAwaitingReset
                ? ""
                : Format.clockCountdown(window.remaining(at: now)),
            isStale: isStale,
            serviceOK: serviceOK
        )
    }

    public static func == (lhs: MenuBarSnapshot, rhs: MenuBarSnapshot) -> Bool {
        lhs.hasData == rhs.hasData
            // Pil yuvarlanmış değeri çiziyor (`remainingPercent`); kıyas da
            // yuvarlamalı, yoksa 45,4 → 45,6 geçişi yeniden çizimi atlıyordu.
            && Int(lhs.usedPercent.rounded()) == Int(rhs.usedPercent.rounded())
            && Int(lhs.weeklyPercent.rounded()) == Int(rhs.weeklyPercent.rounded())
            && lhs.countdownText == rhs.countdownText
            && lhs.isStale == rhs.isStale
            && lhs.serviceOK == rhs.serviceOK
    }
}
