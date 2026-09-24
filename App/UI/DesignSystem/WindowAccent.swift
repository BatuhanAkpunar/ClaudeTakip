import SwiftUI

enum WindowAccent {
    case fiveHour
    case sevenDay

    /// Halka dolgusu.
    var base: Color {
        switch self {
        case .fiveHour: Palette.blue
        case .sevenDay: Palette.orange
        }
    }

    /// Halkanın izi.
    var track: Color {
        switch self {
        case .fiveHour: Palette.blueTrack
        case .sevenDay: Palette.orangeTrack
        }
    }

    /// Grafik eğrisi: halka dolgusundan bir tık koyu (#D98D72 / #DD9D85).
    var line: Color {
        switch self {
        case .fiveHour: Palette.blueLine
        case .sevenDay: Palette.orangeLine
        }
    }

    /// Eğrinin altındaki alan dolgusu.
    var soft: Color {
        switch self {
        case .fiveHour: Palette.blueSoft
        case .sevenDay: Palette.orangeSoft
        }
    }

    /// Seçili sekme çipinin zemini.
    var chip: Color {
        switch self {
        case .fiveHour: Palette.blueChip
        case .sevenDay: Palette.orangeChip
        }
    }

    /// Seçili sekme çipinin metni.
    var ink: Color {
        switch self {
        case .fiveHour: Palette.blueInk
        case .sevenDay: Palette.orangeInk
        }
    }
}

extension Palette {
    private static let criticalThreshold: Double = 90

    static func accent(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical : kind.base
    }

    static func track(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical.opacity(0.18) : kind.track
    }

    static func line(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical : kind.line
    }

    static func soft(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical.opacity(0.1) : kind.soft
    }
}
