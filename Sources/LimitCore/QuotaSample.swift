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
    /// Ek kullanım. Anlamı doğrulanmadığı için okunur ama arayüzde gösterilmez.
    public let extraUsage: Int?

    public init(date: Date, org: String, fiveHour: Int, sevenDay: Int, extraUsage: Int?) {
        self.date = date
        self.org = org
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.extraUsage = extraUsage
    }
}

/// Takip edilen pencere türü.
public enum WindowKind: String, Sendable, CaseIterable {
    case fiveHour
    case sevenDay

    public var duration: TimeInterval {
        switch self {
        case .fiveHour: 5 * 3600
        case .sevenDay: 7 * 24 * 3600
        }
    }
}

extension QuotaSample {
    public func utilization(_ kind: WindowKind) -> Int {
        switch kind {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }
}
