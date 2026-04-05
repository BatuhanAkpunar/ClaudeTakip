import SwiftUI

enum DT {
    enum Colors {
        static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
        static let statusGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let statusOrange = Color(red: 1.0, green: 0.58, blue: 0.0)
        static let statusRed = Color(red: 1.0, green: 0.23, blue: 0.19)
        static let weeklyBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
        static let sonnetPurple = Color(red: 0.55, green: 0.36, blue: 0.96)

        static func statusColor(for remaining: Double) -> Color {
            switch remaining {
            case 0.50...: statusGreen
            case 0.25..<0.50: statusOrange
            default: statusRed
            }
        }

    }


    enum Radius {
        static let card: CGFloat = 10
        static let popoverRadius: CGFloat = 10
    }

    enum Animation {
        static let barFill = SwiftUI.Animation.easeInOut(duration: 0.6)
        static let refreshSpin = SwiftUI.Animation.linear(duration: 0.6)
    }

    enum Size {
        static let popoverWidth: CGFloat = 400
        static let barHeight: CGFloat = 6
    }
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .fill(isDark
                          ? Color.white.opacity(0.12)
                          : Color.white.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .strokeBorder(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.22),
                                   Color.white.opacity(0.08)]
                                : [Color.black.opacity(0.08),
                                   Color.black.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isDark ? .black.opacity(0.35) : .black.opacity(0.08),
                radius: isDark ? 10 : 6,
                y: 3
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}

// MARK: - Popover Background

struct PopoverBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.popoverRadius)
                    .fill(colorScheme == .dark
                          ? Color(red: 0.11, green: 0.11, blue: 0.12)
                          : Color(red: 0.94, green: 0.94, blue: 0.96))
            )
    }
}

extension View {
    func popoverBG() -> some View {
        modifier(PopoverBackground())
    }
}

// MARK: - Themed Divider

struct ThemedDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.10))
            .frame(height: 0.5)
    }
}
