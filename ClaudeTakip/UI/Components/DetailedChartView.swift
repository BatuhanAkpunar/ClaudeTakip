import SwiftUI

struct DetailedChartView: View {
    let snapshots: [UsageSnapshot]
    let resetDate: Date?
    let windowDuration: TimeInterval
    let color: Color
    let xLabels: [String]
    let predictedDepletionDate: Date?
    var showCapMarker: Bool = false
    /// Draw-on progress: data layers (area, line, excess, end dot) are
    /// revealed up to x ≤ width × drawProgress; projection/cap overlays fade
    /// in after the sweep. 1 = fully drawn (default, snapshot renders).
    var drawProgress: Double = 1
    /// Timing for the draw-on sweep; nil applies drawProgress instantly.
    var drawAnimation: Animation? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            // Chart area with Y-axis labels
            HStack(alignment: .top, spacing: 4) {
                // Y-axis labels
                VStack(alignment: .trailing, spacing: 0) {
                    Spacer().frame(height: 18)
                    ForEach(["100%", "75%", "50%", "25%", "0%"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.62))
                        if label != "0%" {
                            Spacer()
                        }
                    }
                }
                .frame(width: 36, height: 110)

                // Layered chart: static backdrop, left→right-revealed data
                // layer, late-fading overlays. The reveal is a plain mask
                // whose scale animates — genuinely animatable, unlike Canvas
                // closure captures.
                ZStack {
                    Canvas { context, size in
                        drawBackdrop(in: &context, size: size)
                    }
                    Canvas { context, size in
                        drawData(in: &context, size: size)
                    }
                    .mask(alignment: .leading) {
                        Rectangle()
                            .scaleEffect(
                                x: max(0.0001, drawProgress), y: 1,
                                anchor: .leading
                            )
                    }
                    .animation(drawAnimation, value: drawProgress)
                    Canvas { context, size in
                        drawOverlays(in: &context, size: size)
                    }
                    .opacity(drawProgress)
                    .animation(
                        drawAnimation == nil
                            ? nil
                            : .easeOut(duration: 0.3).delay(0.55),
                        value: drawProgress
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(height: 110)
            }

            // X-axis labels
            HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 1)
                HStack {
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 {
                            Spacer()
                        }
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Layered Draw

    private let chartTopPad: CGFloat = 18

    /// Static reference layer — grid lines + ideal diagonal. Always visible
    /// (an empty chart still shows its frame of reference).
    private func drawBackdrop(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let usableH = size.height - chartTopPad
        let bottom = chartTopPad + usableH
        let isDark = colorScheme == .dark

        // --- Grid lines (very subtle) ---
        for fraction in [0.25, 0.50, 0.75, 1.0] {
            let y = chartTopPad + usableH * (1 - fraction)
            var gridLine = Path()
            gridLine.move(to: CGPoint(x: 0, y: y))
            gridLine.addLine(to: CGPoint(x: w, y: y))
            context.stroke(
                gridLine,
                with: .color(.primary.opacity(isDark ? 0.10 : 0.05)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 4])
            )
        }

        // --- Ideal diagonal (more visible) ---
        var idealPath = Path()
        idealPath.move(to: CGPoint(x: 0, y: bottom))
        idealPath.addLine(to: CGPoint(x: w, y: chartTopPad))
        context.stroke(
            idealPath,
            with: .color(.primary.opacity(isDark ? 0.30 : 0.18)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )
    }

    /// Data layer — area fill, smooth line, excess shading, end dot. This is
    /// the layer revealed left → right by the draw-on mask.
    private func drawData(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let usableH = size.height - chartTopPad
        let points = chartPoints(width: w, usableHeight: usableH, topPadding: chartTopPad)
        let bottom = chartTopPad + usableH
        let isDark = colorScheme == .dark

        guard points.count >= 2 else { return }

        // --- Build smooth curve ---
        var linePath = Path()
        linePath.move(to: points[0])
        addSmoothCurve(to: &linePath, through: points)

        // --- Area fill (multi-stop gradient) ---
        var areaPath = Path()
        areaPath.move(to: CGPoint(x: points[0].x, y: bottom))
        areaPath.addLine(to: points[0])
        addSmoothCurve(to: &areaPath, through: points)
        if let last = points.last {
            areaPath.addLine(to: CGPoint(x: last.x, y: bottom))
        }
        areaPath.closeSubpath()

        context.fill(
            areaPath,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0.28),
                    color.opacity(0.16),
                    color.opacity(0.06),
                    color.opacity(0.02),
                ]),
                startPoint: CGPoint(x: 0, y: chartTopPad),
                endPoint: CGPoint(x: 0, y: bottom)
            )
        )

        // --- Main data line (crisp) ---
        context.stroke(
            linePath,
            with: .color(color),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )

        // --- Excess areas (above ideal) — drawn on top of line ---
        drawExcessAreas(in: &context, points: points, w: w, usableH: usableH, topPad: chartTopPad, bottom: bottom, isDark: isDark)

        // --- End dot (single soft halo) ---
        if let last = points.last {
            let glowRect = CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)
            context.fill(Circle().path(in: glowRect), with: .color(color.opacity(0.12)))
            // Solid dot
            let dotRect = CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)
            context.fill(Circle().path(in: dotRect), with: .color(color))
            // White center
            let innerRect = CGRect(x: last.x - 1.5, y: last.y - 1.5, width: 3, height: 3)
            context.fill(Circle().path(in: innerRect), with: .color(.white.opacity(0.9)))
        }
    }

    /// Overlay layer — projection line + cap marker. Fades in after the
    /// draw-on sweep completes.
    private func drawOverlays(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let usableH = size.height - chartTopPad
        let points = chartPoints(width: w, usableHeight: usableH, topPadding: chartTopPad)
        let bottom = chartTopPad + usableH

        guard points.count >= 2 else { return }

        // --- Projection line ---
        drawProjection(in: &context, points: points, w: w, topPad: chartTopPad, bottom: bottom)

        // --- Cap-reached marker ---
        if showCapMarker, let last = points.last {
            drawCapMarker(in: &context, lastPoint: last, w: w, topPad: chartTopPad, bottom: bottom)
        }
    }

    // MARK: - Excess Areas

    private func drawExcessAreas(
        in context: inout GraphicsContext,
        points: [CGPoint], w: CGFloat, usableH: CGFloat,
        topPad: CGFloat, bottom: CGFloat, isDark: Bool
    ) {
        let excessColor = Color(red: 1.0, green: 0.25, blue: 0.20).opacity(isDark ? 0.28 : 0.18)
        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]
            let idealY1 = bottom - (p1.x / w) * usableH
            let idealY2 = bottom - (p2.x / w) * usableH
            let above1 = p1.y < idealY1
            let above2 = p2.y < idealY2

            if above1 && above2 {
                var excess = Path()
                excess.move(to: p1)
                excess.addLine(to: p2)
                excess.addLine(to: CGPoint(x: p2.x, y: idealY2))
                excess.addLine(to: CGPoint(x: p1.x, y: idealY1))
                excess.closeSubpath()
                context.fill(excess, with: .color(excessColor))
            } else if above1 || above2 {
                let dx = p2.x - p1.x
                guard dx > 0 else { continue }
                let denom = (p2.y - p1.y) - (idealY2 - idealY1)
                guard abs(denom) > 0.001 else { continue }
                let t = (idealY1 - p1.y) / denom
                let intersection = CGPoint(
                    x: p1.x + t * dx,
                    y: p1.y + t * (p2.y - p1.y)
                )
                var excess = Path()
                if above1 {
                    excess.move(to: p1)
                    excess.addLine(to: intersection)
                    excess.addLine(to: CGPoint(x: p1.x, y: idealY1))
                } else {
                    excess.move(to: intersection)
                    excess.addLine(to: p2)
                    excess.addLine(to: CGPoint(x: p2.x, y: idealY2))
                }
                excess.closeSubpath()
                context.fill(excess, with: .color(excessColor))
            }
        }
    }

    // MARK: - Projection

    private func drawProjection(
        in context: inout GraphicsContext,
        points: [CGPoint], w: CGFloat, topPad: CGFloat, bottom: CGFloat
    ) {
        guard let depletionDate = predictedDepletionDate,
              let resetDate,
              let last = points.last else { return }

        let windowStart = resetDate.addingTimeInterval(-windowDuration)
        let depElapsed = depletionDate.timeIntervalSince(windowStart)
        let depX = w * min(2, depElapsed / windowDuration)
        let depY: CGFloat = topPad

        // Dashed projection line — transparent to opaque
        var projPath = Path()
        projPath.move(to: last)
        projPath.addLine(to: CGPoint(x: depX, y: depY))
        context.stroke(
            projPath,
            with: .linearGradient(
                Gradient(colors: [
                    DT.Colors.statusRed.opacity(0.08),
                    DT.Colors.statusRed.opacity(0.70)
                ]),
                startPoint: last,
                endPoint: CGPoint(x: depX, y: depY)
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3])
        )

        // Depletion marker
        let clampedDepX = min(depX, w - 2)
        guard clampedDepX >= 0 else { return }

        let markerGlow: [(radius: CGFloat, opacity: Double)] = [
            (8, 0.12), (5, 0.30),
        ]
        for layer in markerGlow {
            let rect = CGRect(
                x: clampedDepX - layer.radius, y: depY - layer.radius,
                width: layer.radius * 2, height: layer.radius * 2
            )
            context.fill(Circle().path(in: rect), with: .color(DT.Colors.statusRed.opacity(layer.opacity)))
        }
        let solidRect = CGRect(x: clampedDepX - 3, y: depY - 3, width: 6, height: 6)
        context.fill(Circle().path(in: solidRect), with: .color(DT.Colors.statusRed))

        // Labels — bottom-right of chart to avoid overflow
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = formatter.string(from: depletionDate)
        let label1 = Text("Estimated Overrun")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DT.Colors.statusRed)
        let label2 = Text(timeStr)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundColor(DT.Colors.statusRed)
        let resolved1 = context.resolve(label1)
        let resolved2 = context.resolve(label2)
        let labelX = w - 4
        context.draw(resolved1, at: CGPoint(x: labelX, y: bottom - 18), anchor: .trailing)
        context.draw(resolved2, at: CGPoint(x: labelX, y: bottom - 8), anchor: .trailing)
    }

    // MARK: - Cap-Reached Marker

    /// Draws a vertical freeze line at the last recorded snapshot and a
    /// "Limit reached" label pinned to the bottom-right of the chart. Used
    /// when the quota hit 100% and the chart should stop tracking — the
    /// freeze line visually anchors where the cap landed so the flat-line at
    /// the top doesn't look like live data, while the bottom-right label
    /// mirrors the "Estimated Overrun" placement for consistency.
    private func drawCapMarker(
        in context: inout GraphicsContext,
        lastPoint: CGPoint,
        w: CGFloat, topPad: CGFloat, bottom: CGFloat
    ) {
        let markerColor = DT.Colors.statusRed

        // Vertical dashed freeze line
        var line = Path()
        line.move(to: CGPoint(x: lastPoint.x, y: topPad))
        line.addLine(to: CGPoint(x: lastPoint.x, y: bottom))
        context.stroke(
            line,
            with: .color(markerColor.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
        )

        // "Limit reached" label — bottom-right of chart, matching the
        // placement used by drawProjection for "Estimated Overrun".
        let label = Text(String(localized: "Limit reached", bundle: .app))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(markerColor)
        let resolved = context.resolve(label)
        context.draw(resolved, at: CGPoint(x: w - 4, y: bottom - 8), anchor: .trailing)
    }

    // MARK: - Smooth Curve (Catmull-Rom)

    private func addSmoothCurve(to path: inout Path, through points: [CGPoint]) {
        guard points.count >= 2 else { return }

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        let tension: CGFloat = 0.3
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            // Control points clamped to the segment's bounding box (see ChartMath).
            let (cp1, cp2) = ChartMath.controlPoints(p0: p0, p1: p1, p2: p2, p3: p3, tension: tension)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }

    // MARK: - Chart Points

    private func chartPoints(width: CGFloat, usableHeight: CGFloat, topPadding: CGFloat) -> [CGPoint] {
        ChartMath.points(
            snapshots: snapshots,
            resetDate: resetDate,
            windowDuration: windowDuration,
            width: width,
            usableHeight: usableHeight,
            topPadding: topPadding
        )
    }
}
