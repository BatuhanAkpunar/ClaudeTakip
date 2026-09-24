import Foundation

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

    /// Sıfırlanma anından geriye sayılan pencere başlangıcı.
    public func windowStart(resettingAt reset: Date) -> Date {
        reset.addingTimeInterval(-duration)
    }
}
