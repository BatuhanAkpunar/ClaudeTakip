import SwiftUI

enum DT {
    // MARK: - Colors (Cyberpunk)
    enum Colors {
        // Neon accent colors
        static let neonCyan = Color(red: 0.0, green: 0.94, blue: 1.0)       // #00F0FF
        static let neonMagenta = Color(red: 1.0, green: 0.18, blue: 0.47)   // #FF2D78
        static let neonAmber = Color(red: 1.0, green: 0.72, blue: 0.0)      // #FFB800
        static let neonPurple = Color(red: 0.66, green: 0.33, blue: 0.97)   // #A855F7
        static let neonGreen = Color(red: 0.20, green: 1.0, blue: 0.60)     // #33FF99

        // Status colors (adaptive — neon on dark, muted on light)
        static let statusGreen = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 1)   // Neon cyan
                : NSColor(red: 0.0, green: 0.65, blue: 0.72, alpha: 1)  // Muted cyan
        })
        static let statusOrange = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1)   // Neon amber
                : NSColor(red: 0.80, green: 0.55, blue: 0.0, alpha: 1)  // Muted amber
        })
        static let statusRed = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1.0, green: 0.18, blue: 0.47, alpha: 1)  // Neon magenta
                : NSColor(red: 0.82, green: 0.12, blue: 0.38, alpha: 1) // Muted magenta
        })
        static let weeklyPurple = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1) // Neon purple
                : NSColor(red: 0.50, green: 0.22, blue: 0.82, alpha: 1) // Muted purple
        })

        static func statusColor(for remaining: Double) -> Color {
            switch remaining {
            case 0.50...: return statusGreen
            case 0.25..<0.50: return statusOrange
            default: return statusRed
            }
        }

        // Surface colors
        static let cardBackground = Color.primary.opacity(0.05)
        static let cardBorder = Color.primary.opacity(0.10)
        static let trackBackground = Color.primary.opacity(0.07)
        static let hoverHighlight = Color.primary.opacity(0.08)
        static let divider = Color.primary.opacity(0.08)

        // Glow effects (neon glow shadows)
        static let glowCyan = Color(red: 0.0, green: 0.94, blue: 1.0).opacity(0.4)
        static let glowMagenta = Color(red: 1.0, green: 0.18, blue: 0.47).opacity(0.4)
        static let glowAmber = Color(red: 1.0, green: 0.72, blue: 0.0).opacity(0.4)
        static let glowPurple = Color(red: 0.66, green: 0.33, blue: 0.97).opacity(0.4)
    }

    // MARK: - Typography (tech/monospace-forward)
    enum Typography {
        static let heroPercent = Font.system(size: 56, weight: .heavy, design: .monospaced)
        static let heroSubtitle = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let cardValue = Font.system(size: 14, weight: .bold, design: .monospaced)
        static let label = Font.system(size: 12, weight: .medium)
        static let body = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 10, weight: .medium)
        static let smallCaption = Font.system(size: 9, weight: .medium)
        static let sectionTitle = Font.system(size: 10, weight: .heavy, design: .monospaced)
        static let footerAction = Font.system(size: 11, weight: .medium)
        static let toggleLabel = Font.system(size: 12, weight: .regular)
        static let tooltipBody = Font.system(size: 11, weight: .regular)
        static let tooltipTitle = Font.system(size: 11, weight: .semibold)
    }

    // MARK: - Spacing
    enum Spacing {
        static let popoverPadding: CGFloat = 20
        static let cardPaddingH: CGFloat = 10
        static let cardPaddingV: CGFloat = 8
        static let sectionGap: CGFloat = 14
        static let toggleRowPaddingV: CGFloat = 7
        static let itemGap: CGFloat = 8
    }

    // MARK: - Radius
    enum Radius {
        static let popover: CGFloat = 14
        static let card: CGFloat = 8
        static let toggle: CGFloat = 10
        static let checkbox: CGFloat = 4
        static let iconButton: CGFloat = 6
    }

    // MARK: - Animation
    enum Animation {
        static let progressFill = SwiftUI.Animation.easeInOut(duration: 0.6)
        static let hover = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let notesSlide = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
        static let refreshSpin = SwiftUI.Animation.linear(duration: 0.6)
    }

    // MARK: - Sizes
    enum Size {
        static let popoverWidth: CGFloat = 320
        static let popoverWithNotesWidth: CGFloat = 590
        static let notesPanelWidth: CGFloat = 270
        static let progressBarHeight: CGFloat = 6
        static let timeMarkerWidth: CGFloat = 2
        static let timeMarkerHeight: CGFloat = 10
        static let statusDotSize: CGFloat = 7
        static let iconButtonSize: CGFloat = 28
        static let toggleWidth: CGFloat = 32
        static let toggleHeight: CGFloat = 19
        static let checkboxSize: CGFloat = 15
    }
}
