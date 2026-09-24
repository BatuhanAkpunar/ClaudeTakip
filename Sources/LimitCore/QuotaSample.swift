import Foundation

/// Claude Desktop'ın `plan-usage-history.json` dosyasındaki tek bir ölçüm.
///
/// Dosya şeması kullanıcının makinesinde 3466 örnek üzerinde doğrulandı:
/// `{ "t": 1787344332573, "org": "...", "u": { "fh": 48, "sd": 97, "xu": 100 } }`
public struct QuotaSample: Sendable, Equatable {
    public let date: Date
    public let org: String
    /// 5 saatlik pencere kullanımı, 0-100.
    public let fiveHour: Int
    /// 7 günlük pencere kullanımı, 0-100.
    public let sevenDay: Int
    /// Claude Desktop'ın `xu` alanı; anlamı belgesiz, yalnızca ekstra kullanım
    /// açıkken cüzdan çubuğunda yorumlanır.
    public let extraUsage: Int?

    public init(date: Date, org: String, fiveHour: Int, sevenDay: Int, extraUsage: Int?) {
        self.date = date
        self.org = org
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.extraUsage = extraUsage
    }
}

extension QuotaSample {
    /// Sunucu okumasından arşiv örneği; iki pencereden biri yoksa nil.
    public init?(server usage: ServerUsage, date: Date, org: String) {
        guard let five = usage.fiveHour, let seven = usage.sevenDay else { return nil }
        self.init(
            date: date,
            org: org,
            fiveHour: Int(five.utilization.rounded()),
            sevenDay: Int(seven.utilization.rounded()),
            extraUsage: usage.wallet?.roundedUtilization
        )
    }

    public func utilization(_ kind: WindowKind) -> Int {
        switch kind {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }
}
