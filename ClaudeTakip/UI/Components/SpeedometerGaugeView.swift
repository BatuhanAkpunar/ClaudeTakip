import SwiftUI

/// Half-circle gauge showing usage rate with gradient color fill (0x – 2x+).
struct SpeedometerGaugeView: View {
    let rate: Double
    let title: String
    let badgeText: String
    let badgeColor: Color
    let deviationText: String
    var limitReached: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private let arcStroke: CGFloat = 11
    private let arcHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.primary.opacity(0.50))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack(alignment: .bottom) {
                gaugeCanvas
                let clamped = min(max(rate, 0), 2.0)
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text(rateNumber(clamped))
                        .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                        .tracking(-0.5)
                    Text(rateSuffix(clamped))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(rateColor(for: clamped).opacity(0.7))
                }
                .foregroundStyle(rateColor(for: clamped))
                .offset(y: 2)
            }
            .frame(height: arcHeight)

            Spacer(minLength: 0)
                .padding(.top, 4)

            VStack(spacing: 4) {
                // Deviation with directional arrow — fixed height to keep badges aligned
                HStack(spacing: 3) {
                    Image(systemName: deviationArrow)
                        .font(.system(size: 10.5, weight: .medium))
                    Text(deviationText)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(deviationColor)
                .opacity(limitReached ? 0 : 1)
                .frame(height: 16)

                badge
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(height: 122)
    }

    // MARK: - Badge

    private var badge: some View {
        Text(badgeText)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(badgeColor.opacity(colorScheme == .dark ? 0.9 : 1.0))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Capsule().fill(badgeColor.opacity(colorScheme == .dark ? 0.15 : 0.15)))
    }

    // MARK: - Canvas

    private var gaugeCanvas: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let centerX = w / 2
            let centerY = h * 0.92
            let radius = min(centerX - arcStroke, centerY - arcStroke)
            let center = CGPoint(x: centerX, y: centerY)

            // Background track (full 180°)
            drawArc(in: &context, center: center, radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0),
                    color: Color.primary.opacity(0.06), lineWidth: arcStroke)

            // Filled smooth gradient arc up to current rate (full arc when limit reached)
            let arcRate = limitReached ? 2.0 : min(max(rate, 0), 2.0)
            let fillFraction = arcRate / 2.0

            // Glow arc (wide, soft) — drawn first behind main arc
            let segments = 50
            for i in 0..<segments {
                let segStartFrac = Double(i) / Double(segments)
                let segEndFrac = Double(i + 1) / Double(segments)
                let segEnd = min(segEndFrac, fillFraction)
                guard segEnd > segStartFrac else { continue }

                let midRate = ((segStartFrac + segEnd) / 2) * 2.0
                let segColor = gradientArcColor(at: midRate)

                let startDeg = 180.0 * (1 - segStartFrac)
                let endDeg = 180.0 * (1 - segEnd)

                // Glow layer
                drawArc(in: &context, center: center, radius: radius,
                        startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                        color: segColor.opacity(0.14), lineWidth: arcStroke + 2)

                // Main arc
                drawArc(in: &context, center: center, radius: radius,
                        startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                        color: segColor, lineWidth: arcStroke)
            }

            // Ideal marker at top (1.0x = midpoint = 90°)
            let tickInnerR = radius - arcStroke / 2 - 1
            let tickOuterR = radius + arcStroke / 2 + 1
            let tickX = centerX // cos(90°) = 0
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: tickX, y: centerY - tickInnerR))
            tickPath.addLine(to: CGPoint(x: tickX, y: centerY - tickOuterR))
            context.stroke(tickPath, with: .color(.primary.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            let idealLabel = Text("1x")
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.45))
            let resolvedIdeal = context.resolve(idealLabel)
            context.draw(resolvedIdeal, at: CGPoint(x: tickX, y: centerY - tickOuterR - 7), anchor: .center)

            // Glowing end cap at current position
            if fillFraction > 0.01 {
                let capAngle = Double.pi * (1 - fillFraction)
                let capX = centerX + cos(capAngle) * radius
                let capY = centerY - sin(capAngle) * radius

                // Glow layers
                let glowLayers: [(radius: CGFloat, opacity: Double)] = [
                    (7, 0.08), (5, 0.15), (3.5, 0.25),
                ]
                let endColor = gradientArcColor(at: arcRate)
                for layer in glowLayers {
                    let rect = CGRect(x: capX - layer.radius, y: capY - layer.radius,
                                      width: layer.radius * 2, height: layer.radius * 2)
                    context.fill(Circle().path(in: rect),
                                 with: .color(endColor.opacity(layer.opacity)))
                }
                // Solid dot
                let dotSize: CGFloat = 4
                let dotRect = CGRect(x: capX - dotSize / 2, y: capY - dotSize / 2,
                                     width: dotSize, height: dotSize)
                context.fill(Circle().path(in: dotRect), with: .color(endColor))
                // White center
                let innerSize: CGFloat = 2
                let innerRect = CGRect(x: capX - innerSize / 2, y: capY - innerSize / 2,
                                       width: innerSize, height: innerSize)
                context.fill(Circle().path(in: innerRect),
                             with: .color(.white.opacity(0.9)))
            }
        }
        .animation(DT.Animation.barFill, value: rate)
    }

    // MARK: - Helpers

    private func drawArc(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        startAngle: Angle,
        endAngle: Angle,
        color: Color,
        lineWidth: CGFloat? = nil
    ) {
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: -startAngle, endAngle: -endAngle,
                    clockwise: false)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth ?? arcStroke, lineCap: .round))
    }

    // Deviation color: direction-based semantics
    // Positive = faster than ideal → warning (orange/red by magnitude)
    // Negative = slower than ideal → good (green)
    // Near zero = neutral
    private var deviationColor: Color {
        let deviation = rate - 1.0
        if deviation <= 0.03 { return Color.primary.opacity(0.50) }
        return deviation > 0.30 ? DT.Colors.statusRed : DT.Colors.statusOrange
    }

    private var deviationArrow: String {
        rate > 1.03 ? "arrow.up.right" : "equal"
    }

    private func rateNumber(_ value: Double) -> String {
        if value >= 1.95 { return "2" }
        let truncated = (value * 10).rounded(.down) / 10
        if abs(truncated - truncated.rounded()) < 0.05 && truncated >= 0 {
            return String(format: "%.0f", truncated)
        }
        return String(format: "%.1f", truncated)
    }

    private func rateSuffix(_ value: Double) -> String {
        value >= 1.95 ? "x+" : "x"
    }

    private func rateColor(for value: Double) -> Color {
        gradientArcColor(at: value)
    }

    private func gradientArcColor(at rate: Double) -> Color {
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
}
