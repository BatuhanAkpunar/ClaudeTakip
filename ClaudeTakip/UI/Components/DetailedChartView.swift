import SwiftUI

struct DetailedChartView: View {
    let snapshots: [UsageSnapshot]
    let resetDate: Date?
    let windowDuration: TimeInterval
    let color: Color
    let xLabels: [String]
    let predictedDepletionDate: Date?

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
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.7))
                        if label != "0%" {
                            Spacer()
                        }
                    }
                }
                .frame(width: 32, height: 110)

                // Canvas chart
                ZStack {
                    Canvas { context, size in
                        drawChart(in: &context, size: size)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(height: 110)
            }

            // X-axis labels
            HStack(spacing: 0) {
                Color.clear.frame(width: 36, height: 1)
                HStack {
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 {
                            Spacer()
                        }
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Main Draw

    private func drawChart(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let topPad: CGFloat = 18
        let usableH = h - topPad
        let points = chartPoints(width: w, usableHeight: usableH, topPadding: topPad)
        let bottom = topPad + usableH

        let isDark = colorScheme == .dark

        // --- Grid lines (very subtle) ---
        for fraction in [0.25, 0.50, 0.75, 1.0] {
            let y = topPad + usableH * (1 - fraction)
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
        idealPath.addLine(to: CGPoint(x: w, y: topPad))
        context.stroke(
            idealPath,
            with: .color(.primary.opacity(isDark ? 0.30 : 0.18)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )

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
                    color.opacity(0.90),
                    color.opacity(0.60),
                    color.opacity(0.25),
                    color.opacity(0.03),
                ]),
                startPoint: CGPoint(x: 0, y: topPad),
                endPoint: CGPoint(x: 0, y: bottom)
            )
        )

        // --- Line glow (subtle) ---
        context.stroke(
            linePath,
            with: .color(color.opacity(0.18)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )

        // --- Main data line (crisp) ---
        context.stroke(
            linePath,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )

        // --- Excess areas (above ideal) — drawn on top of line ---
        drawExcessAreas(in: &context, points: points, w: w, usableH: usableH, topPad: topPad, bottom: bottom, isDark: isDark)

        // --- Glowing end dot ---
        if let last = points.last {
            let glowLayers: [(radius: CGFloat, opacity: Double)] = [
                (8, 0.06),
                (5, 0.12),
                (3.5, 0.25),
            ]
            for layer in glowLayers {
                let rect = CGRect(
                    x: last.x - layer.radius, y: last.y - layer.radius,
                    width: layer.radius * 2, height: layer.radius * 2
                )
                context.fill(Circle().path(in: rect), with: .color(color.opacity(layer.opacity)))
            }
            // Solid ring
            let dotRect = CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)
            context.fill(Circle().path(in: dotRect), with: .color(color))
            // White center
            let innerRect = CGRect(x: last.x - 1.5, y: last.y - 1.5, width: 3, height: 3)
            context.fill(Circle().path(in: innerRect), with: .color(.white.opacity(0.9)))
        }

        // --- Projection line ---
        drawProjection(in: &context, points: points, w: w, topPad: topPad, bottom: bottom)
    }

    // MARK: - Excess Areas

    private func drawExcessAreas(
        in context: inout GraphicsContext,
        points: [CGPoint], w: CGFloat, usableH: CGFloat,
        topPad: CGFloat, bottom: CGFloat, isDark: Bool
    ) {
        let excessColor = Color(red: 1.0, green: 0.25, blue: 0.20).opacity(isDark ? 0.35 : 0.25)
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

        // Dashed projection line
        var projPath = Path()
        projPath.move(to: last)
        projPath.addLine(to: CGPoint(x: depX, y: depY))
        context.stroke(
            projPath,
            with: .color(DT.Colors.statusRed.opacity(0.5)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3])
        )

        // Depletion marker
        let clampedDepX = min(depX, w - 2)
        guard clampedDepX >= 0 else { return }

        let markerGlow: [(radius: CGFloat, opacity: Double)] = [
            (12, 0.08), (8, 0.16), (5, 0.35),
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
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(DT.Colors.statusRed)
        let label2 = Text(timeStr)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(DT.Colors.statusRed)
        let resolved1 = context.resolve(label1)
        let resolved2 = context.resolve(label2)
        let labelX = w - 4
        context.draw(resolved1, at: CGPoint(x: labelX, y: bottom - 18), anchor: .trailing)
        context.draw(resolved2, at: CGPoint(x: labelX, y: bottom - 8), anchor: .trailing)
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

            // Clamp control point x to [p1.x, p2.x] to prevent overshoot
            // when there's a large gap between sparse data points
            let cp1 = CGPoint(
                x: max(p1.x, min(p2.x, p1.x + (p2.x - p0.x) * tension)),
                y: p1.y + (p2.y - p0.y) * tension
            )
            let cp2 = CGPoint(
                x: max(p1.x, min(p2.x, p2.x - (p3.x - p1.x) * tension)),
                y: p2.y - (p3.y - p1.y) * tension
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }

    // MARK: - Chart Points

    private func chartPoints(width: CGFloat, usableHeight: CGFloat, topPadding: CGFloat) -> [CGPoint] {
        guard let resetDate, !snapshots.isEmpty else { return [] }
        let windowStart = resetDate.addingTimeInterval(-windowDuration)

        return snapshots.compactMap { snapshot in
            let elapsed = snapshot.timestamp.timeIntervalSince(windowStart)
            guard elapsed >= 0 else { return nil }
            let xFraction = min(1, elapsed / windowDuration)
            let yFraction = max(0, min(1, snapshot.usage))
            return CGPoint(x: width * xFraction, y: topPadding + usableHeight * (1 - yFraction))
        }
    }
}
