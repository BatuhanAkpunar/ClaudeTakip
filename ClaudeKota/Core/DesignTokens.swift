import SwiftUI

enum DT {
    // MARK: - Colors (adaptive)
    enum Colors {
        static let statusGreen = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1) // #4ade80
                : NSColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 1) // #16a34a
        })
        static let statusOrange = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1) // #f59e0b
                : NSColor(red: 0.85, green: 0.47, blue: 0.02, alpha: 1) // #d97706
        })
        static let statusRed = Color(red: 0.94, green: 0.27, blue: 0.27)     // #ef4444
        static let weeklyBlue = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1) // #60a5fa
                : NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1) // #3b82f6
        })

        static func statusColor(for remaining: Double) -> Color {
            switch remaining {
            case 0.50...: return statusGreen
            case 0.25..<0.50: return statusOrange
            default: return statusRed
            }
        }

        // Surface colors
        static let cardBackground = Color.primary.opacity(0.04)
        static let cardBorder = Color.primary.opacity(0.08)
        static let trackBackground = Color.primary.opacity(0.06)
        static let hoverHighlight = Color.primary.opacity(0.06)
        static let divider = Color.primary.opacity(0.06)
    }

    // MARK: - Typography
    enum Typography {
        static let heroPercent = Font.system(size: 52, weight: .bold, design: .monospaced)
        static let cardValue = Font.system(size: 15, weight: .semibold, design: .monospaced)
        static let label = Font.system(size: 12, weight: .medium)
        static let body = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 10, weight: .regular)
        static let smallCaption = Font.system(size: 9, weight: .regular)
        static let sectionTitle = Font.system(size: 10, weight: .semibold)
        static let footerAction = Font.system(size: 11, weight: .regular)
    }

    // MARK: - Spacing
    enum Spacing {
        static let popoverPadding: CGFloat = 18
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
    }

    // MARK: - Sizes
    enum Size {
        static let popoverWidth: CGFloat = 300
        static let popoverWithNotesWidth: CGFloat = 560
        static let notesPanelWidth: CGFloat = 260
        static let progressBarHeight: CGFloat = 5
        static let timeMarkerWidth: CGFloat = 2
        static let timeMarkerHeight: CGFloat = 9
        static let statusDotSize: CGFloat = 7
        static let iconButtonSize: CGFloat = 26
        static let toggleWidth: CGFloat = 32
        static let toggleHeight: CGFloat = 19
        static let checkboxSize: CGFloat = 15
    }
}
