import SwiftUI

enum DT {
    enum Colors {
        static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
        // Theme refresh: status hues a touch deeper for contrast on the
        // richer aurora canvas; identity hues (Sonnet/Extra) more saturated
        // so the data fills pop in both schemes.
        static let statusGreen = Color(red: 0.14, green: 0.73, blue: 0.33)
        static let statusOrange = Color(red: 1.0, green: 0.56, blue: 0.0)
        static let statusRed = Color(red: 0.96, green: 0.20, blue: 0.16)
        static let weeklyBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
        static let sonnetPurple = Color(red: 0.44, green: 0.35, blue: 0.97)
        static let extraBlue = Color(nsColor: NSColor(
            name: nil,
            dynamicProvider: { $0.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.34, green: 0.62, blue: 0.96, alpha: 1.0)
                : NSColor(red: 0.05, green: 0.42, blue: 0.80, alpha: 1.0)
            }
        ))

        // Activity-ring TIP colors — Apple's rings run a 2-stop angular
        // gradient from the base hue (12 o'clock) to a clearly DIFFERENT
        // bright tone at the moving tip (teardown: Move #E10014→#FF3287,
        // Exercise #37DC00→#B7FF00, Stand #00BAE1→#00FAD0). These are those
        // journeys re-pitched for a light background, one per window.
        static let ringTipLime = Color(red: 0.608, green: 0.831, blue: 0.110)    // #9BD41C ← session green
        static let ringTipPink = Color(red: 0.941, green: 0.337, blue: 0.561)    // #F0568F ← weekly coral
        static let ringTipMagenta = Color(red: 0.847, green: 0.294, blue: 0.878) // #D84BE0 ← sonnet purple
        static let ringTipAqua = Color(red: 0.043, green: 0.776, blue: 0.722)    // #0BC6B8 ← extra blue

        // Aurora gradient partners — bar/donut fills sweep from the identity
        // or status hue into these (owner: "aurora gradient tonları").
        static let auroraTeal = Color(red: 0.176, green: 0.831, blue: 0.749)    // #2DD4BF ← green
        static let auroraPink = Color(red: 0.957, green: 0.447, blue: 0.714)    // #F472B6 ← orange
        static let auroraMagenta = Color(red: 0.855, green: 0.267, blue: 0.678) // #DA44AD ← red
        static let auroraViolet = Color(red: 0.780, green: 0.518, blue: 0.980)  // #C784FA ← sonnet
        static let auroraCyan = Color(red: 0.133, green: 0.827, blue: 0.933)    // #22D3EE ← extra

        // Aurora Ambient canvas — the popover base under the gradient-mesh
        // wash (see PopoverBackground). Light leans a touch cool so the
        // aurora tints read as atmosphere, not color casts.
        static let canvasLight = Color(red: 0.965, green: 0.965, blue: 0.976)  // #F6F6F9
        static let canvasDark = Color(red: 0.080, green: 0.080, blue: 0.096)   // #141418

        static func statusColor(for remaining: Double) -> Color {
            switch remaining {
            case 0.50...: statusGreen
            case 0.25..<0.50: statusOrange
            default: statusRed
            }
        }

        /// Aurora sweep partner for a status color chosen via statusColor(for:).
        static func auroraPartner(for remaining: Double) -> Color {
            switch remaining {
            case 0.50...: auroraTeal
            case 0.25..<0.50: auroraPink
            default: auroraMagenta
            }
        }

    }


    enum Radius {
        static let card: CGFloat = 12
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
                RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .fill(isDark
                          ? Color.white.opacity(0.07)
                          : Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .strokeBorder(
                        isDark
                            ? Color.white.opacity(0.10)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isDark ? .black.opacity(0.10) : .black.opacity(0.05),
                radius: isDark ? 8 : 5,
                y: 2
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}

// MARK: - Popover Background

/// Aurora Ambient canvas — a whisper-level gradient mesh (Stripe/Linear-style
/// "aurora UI") built from the app's OWN aurora partner hues, so the cards
/// float on atmosphere without a new dominant color. Radial fills fade to
/// clear, so there are no hard bands in either scheme.
struct PopoverBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: DT.Radius.popoverRadius)
        content
            .background(
                shape
                    .fill(isDark ? DT.Colors.canvasDark : DT.Colors.canvasLight)
                    .overlay(
                        // Theme refresh: aurora wash raised ~1.5× so the
                        // canvas reads as atmosphere, not near-white.
                        ZStack {
                            RadialGradient(
                                colors: [DT.Colors.auroraViolet.opacity(isDark ? 0.20 : 0.15), .clear],
                                center: .topLeading, startRadius: 0, endRadius: 300
                            )
                            RadialGradient(
                                colors: [DT.Colors.auroraTeal.opacity(isDark ? 0.15 : 0.12), .clear],
                                center: .topTrailing, startRadius: 0, endRadius: 280
                            )
                            RadialGradient(
                                colors: [DT.Colors.auroraPink.opacity(isDark ? 0.12 : 0.09), .clear],
                                center: .bottom, startRadius: 0, endRadius: 300
                            )
                        }
                        .clipShape(shape)
                    )
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
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
            .frame(height: 0.5)
    }
}
