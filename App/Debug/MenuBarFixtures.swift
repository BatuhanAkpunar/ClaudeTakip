import Foundation
import LimitCore

#if DEBUG

/// Önizleme ve self-test için ortak menü çubuğu anlık görüntüleri.
extension MenuBarSnapshot {
    /// Verilen kullanımla tam bir anlık görüntü (geri sayım "3:54").
    static func sample(used: Double, serviceOK: Bool = true, stale: Bool = false) -> MenuBarSnapshot {
        MenuBarSnapshot(hasData: true, usedPercent: used, weeklyPercent: 0,
                        countdownText: "3:54", isStale: stale, serviceOK: serviceOK)
    }

    /// Veri yokken çizilen anlık görüntü.
    static let noData = MenuBarSnapshot(hasData: false, usedPercent: 0, countdownText: "", isStale: false)
}

#endif
