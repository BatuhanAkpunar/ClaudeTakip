import SwiftUI

// MARK: - Shared Timer-Arc Geometry

/// Gauge-style arc: 280° sweep starting at 130° (bottom-left, clockwise),
/// leaving an 80° gap centered at the bottom — Apple Timer reference. Every
/// gauge column shares this geometry so all pager pages read as one
/// instrument family.
enum TimerArc {
    static let start: Double = 130
    static let span: Double = 280
    /// Fraction of the full circle the arc occupies (angular-gradient space).
    static let circleFraction: Double = span / 360
}

// MARK: - Timer Gauge Column

/// One instrument column shared by the Overview and Rate pager pages:
/// title ladder, 280° arc with a bottom gap, a thumb chip riding the arc
/// end, value + status badge in the center hole, and a label + capsule
/// token below the ring. Both pages literally render this one view, so
/// their anatomy can never drift apart.
struct TimerGaugeColumn: View {
    /// Arc paint recipes.
    enum ArcFill {
        /// Status hue sweeping into its aurora partner (Overview gauges) —
        /// the gradient end rides the moving arc end.
        case aurora(base: Color, partner: Color)
        /// Fixed-in-space semantic rate ramp green → amber → orange-red →
        /// red (Rate gauges) — the hue encodes the RATE POSITION on the
        /// dial, not the arc length, with an ideal tick at the midpoint.
        case rateRamp
    }

    /// Entrance-gated arc fill (0…1): the caller passes 0 while hidden and
    /// the real fraction on reveal; `fillAnimation` sweeps the change.
    let fraction: Double
    let fill: ArcFill
    let title: String
    let centerText: String
    /// nil → neutral primary (Overview times); Rate passes the ramp hue.
    var centerColor: Color? = nil
    let badgeText: String
    let badgeColor: Color
    /// Text inside the thumb chip riding the arc end ("63%", "+13%").
    let thumbText: String
    let thumbColor: Color
    let tokenIcon: String
    let tokenLabel: String
    let tokenValue: String
    var tokenValueIcon: String? = nil
    /// nil → neutral primary (reset times); Rate passes the severity tint.
    var tokenValueColor: Color? = nil
    /// Entrance-fill timing from the unified entrance system. nil applies
    /// the fill instantly (hidden reset / snapshot renders).
    var fillAnimation: Animation? = nil

    @Environment(\.colorScheme) private var colorScheme

    private let ringSize: CGFloat = 120
    private let ringStroke: CGFloat = 14
    /// Stroke centerline radius — the thumb modifier rides this.
    private var ringRadius: CGFloat { (ringSize - ringStroke) / 2 }

    var body: some View {
        VStack(spacing: 4) {
            // Title centered — same ladder on every page.
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.primary.opacity(0.70))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack {
                // Track — 280° arc, gap centered at the bottom. The inset
                // keeps the centered stroke inside the frame so the stroke
                // CENTERLINE radius is exactly (ringSize - ringStroke) / 2 —
                // the same radius the thumb modifier rides on.
                Circle()
                    .inset(by: ringStroke / 2)
                    .trim(from: 0, to: TimerArc.circleFraction)
                    .stroke(
                        Color.primary.opacity(0.08),
                        style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(TimerArc.start))

                // Progress arc.
                Circle()
                    .inset(by: ringStroke / 2)
                    .trim(from: 0, to: min(1, max(0, fraction)) * TimerArc.circleFraction)
                    .stroke(
                        arcGradient,
                        style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(TimerArc.start))
                    .shadow(color: thumbColor.opacity(0.32), radius: 5)
                    .animation(fillAnimation, value: fraction)

                // Ideal tick (rate ramp only) — 1.0x sits at the arc's
                // MIDPOINT, which for the 130°+280° geometry is exactly
                // 12 o'clock; a small primary tick crossing the stroke.
                if case .rateRamp = fill {
                    Rectangle()
                        .fill(Color.primary.opacity(0.30))
                        .frame(width: 1.5, height: ringStroke + 6)
                        .offset(y: -ringRadius)
                }

                // Center — value + status badge. The frame keeps both inside
                // the ring hole; the badge gets an explicit maxWidth so its
                // capsule keeps ≥6 pt clearance from the fat stroke.
                VStack(spacing: 4) {
                    Text(centerText)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(centerColor ?? Color.primary.opacity(0.90))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    statusBadge
                        .frame(maxWidth: 72)
                }
                .frame(width: ringSize - 2 * ringStroke - 12)

                // Thumb — its center sits exactly on the stroke centerline
                // (radius = (size - stroke) / 2) at the end angle; the text
                // is never rotated.
                thumb
                    .modifier(TimerArcThumbPosition(
                        fraction: min(1, max(0, fraction)),
                        radius: ringRadius
                    ))
                    .animation(fillAnimation, value: fraction)
            }
            .frame(width: ringSize, height: ringSize)
            // Room for the thumb overhanging the stroke (dia = stroke + 10).
            // The negative bottom padding reclaims the arc's empty bottom-gap
            // band (~15 pt inside the square frame) so the token sits ≤10 pt
            // under the visible arc instead of floating far below.
            .padding(.horizontal, 6)
            .padding(.top, 7)
            .padding(.bottom, -11)

            token
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Arc Gradient

    private var arcGradient: AngularGradient {
        switch fill {
        case .aurora(let base, let partner):
            // Rich 3-stop sweep: status hue → mid blend → aurora partner;
            // the min span keeps short arcs calm.
            return AngularGradient(
                colors: [base, base.mix(with: partner, by: 0.55), partner],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(TimerArc.span * max(0.25, min(1, max(0, fraction))))
            )
        case .rateRamp:
            // Fixed-in-space semantics: green at 0x (arc start), amber at
            // 1.0x (midpoint), orange-red at 1.5x, red at 2x (arc end). The
            // arc occupies location 0…span/360 of the angular space; the
            // tail stops are a wrap guard — the round start cap overhangs a
            // few degrees BELOW trim 0, sampling the gradient just under
            // location 1.0, so that region stays green to match the 0x end
            // of the ramp.
            let arc = TimerArc.circleFraction
            return AngularGradient(
                stops: [
                    .init(color: Self.rampColor(0.0), location: 0),
                    .init(color: Self.rampColor(1.0), location: 0.5 * arc),
                    .init(color: Self.rampColor(1.5), location: 0.75 * arc),
                    .init(color: Self.rampColor(2.0), location: arc),
                    .init(color: Self.rampColor(2.0), location: 0.86),
                    .init(color: Self.rampColor(0.0), location: 0.95),
                    .init(color: Self.rampColor(0.0), location: 1),
                ],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
        }
    }

    // MARK: - Status Badge

    /// Tinted capsule badge for pacing/severity texts — one look everywhere
    /// ("Ideal", "Limit risk", "Burning too fast", ...).
    private var statusBadge: some View {
        Text(badgeText)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(badgeColor.opacity(colorScheme == .dark ? 0.95 : 1.0))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor.opacity(0.20)))
            .overlay(Capsule().strokeBorder(badgeColor.opacity(0.32), lineWidth: 0.5))
    }

    // MARK: - Thumb

    /// The readout riding the arc end. Same `fraction` as the arc itself —
    /// never a separate calculation. The text sits dead-center in the circle
    /// (plain ZStack centering, no baseline offsets), stays upright, and
    /// scales down for longer strings.
    private var thumb: some View {
        ZStack {
            Circle()
                .fill(thumbColor)
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                .padding(2)
            Text(thumbText)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
        }
        // Diameter tracks the ring stroke (stroke + 10) so the thumb reads
        // attached to the fat arc rather than floating on it.
        .frame(width: ringStroke + 10, height: ringStroke + 10)
        .shadow(color: .black.opacity(0.20), radius: 3)
    }

    // MARK: - Below-Ring Token

    /// Label line (small icon + plain text) OUTSIDE the capsule; only the
    /// bold value lives inside the capsule — "resets in / 2h 13m" on the
    /// Overview, "Ideal = 1.0x / +13% deviation" on the Rate page.
    private var token: some View {
        Group {
            if !tokenValue.isEmpty {
                VStack(spacing: 3) {
                    HStack(spacing: 3.5) {
                        Image(systemName: tokenIcon)
                            .font(.system(size: 10, weight: .medium))
                        Text(tokenLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.primary.opacity(0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    HStack(spacing: 3.5) {
                        if let tokenValueIcon {
                            Image(systemName: tokenValueIcon)
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(tokenValue)
                            .font(.system(size: 11.5, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(tokenValueColor ?? Color.primary.opacity(0.90))
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Rate Semantics (ported from the retired SpeedometerGaugeView)

extension TimerGaugeColumn {
    /// Semantic rate ramp — the hue for a rate position on the 0x–2x dial.
    static func rampColor(_ rate: Double) -> Color {
        let stops: [(rate: Double, r: Double, g: Double, b: Double)] = [
            (0.0,  0.13, 0.78, 0.34),  // green
            (1.0,  0.97, 0.75, 0.08),  // amber
            (1.5,  1.00, 0.35, 0.05),  // orange-red
            (2.0,  0.90, 0.08, 0.05),  // red
        ]
        let c = max(0, min(2.0, rate))
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            if c >= stops[i].rate && c <= stops[i + 1].rate {
                lo = stops[i]; hi = stops[i + 1]; break
            }
        }
        let range = hi.rate - lo.rate
        let t = range > 0 ? (c - lo.rate) / range : 0
        return Color(
            red: lo.r + (hi.r - lo.r) * t,
            green: lo.g + (hi.g - lo.g) * t,
            blue: lo.b + (hi.b - lo.b) * t
        )
    }

    /// Deviation severity tint — direction-based semantics: ≤3% over ideal
    /// reads neutral, >30% over reads red, anything between reads orange.
    static func deviationColor(for rate: Double) -> Color {
        let deviation = rate - 1.0
        if deviation <= 0.03 { return Color.primary.opacity(0.70) }
        return deviation > 0.30 ? DT.Colors.statusRed : DT.Colors.statusOrange
    }

    /// Directional glyph paired with the deviation text.
    static func deviationArrow(for rate: Double) -> String {
        rate > 1.03 ? "arrow.up.right" : "equal"
    }

    /// Center readout for a rate — "0.7x", "1.1x", "2x+" (suffix included).
    static func rateText(_ rate: Double) -> String {
        let clamped = min(max(rate, 0), 2.0)
        if clamped >= 1.95 { return "2x+" }
        let truncated = (clamped * 10).rounded(.down) / 10
        if abs(truncated - truncated.rounded()) < 0.05 && truncated >= 0 {
            return String(format: "%.0fx", truncated)
        }
        return String(format: "%.1fx", truncated)
    }

    /// Signed compact deviation percent for the thumb chip — "+13%", "0%",
    /// "−30%". Truncates like the view model's deviation text so the thumb
    /// and the capsule below can never disagree ("+13%" ↔ "+13% deviation").
    static func deviationPercentText(for rate: Double) -> String {
        let clamped = min(max(rate, 0), 2.0)
        let pct = Int((clamped - 1.0) * 100)
        if pct > 0 { return "+\(pct)%" }
        if pct < 0 { return "\u{2212}\(-pct)%" }
        return "0%"
    }
}

// MARK: - Arc Thumb Position

/// Pins the thumb to the moving end of the timer arc. Animatable so the
/// thumb follows the arc (not a straight chord) while the entrance fill
/// runs, and the containing view is never rotated — the thumb text stays
/// upright.
struct TimerArcThumbPosition: ViewModifier, @preconcurrency Animatable {
    var fraction: Double
    var radius: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = min(1, max(0, fraction))
        let angle = Angle.degrees(TimerArc.start + TimerArc.span * clamped).radians
        return content.offset(
            x: CGFloat(cos(angle)) * radius,
            y: CGFloat(sin(angle)) * radius
        )
    }
}
