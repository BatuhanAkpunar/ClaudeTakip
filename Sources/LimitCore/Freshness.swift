import Foundation

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
