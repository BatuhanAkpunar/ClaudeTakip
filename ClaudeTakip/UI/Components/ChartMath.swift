import CoreGraphics
import Foundation

/// Pure geometry for the usage-history chart, extracted from `DetailedChartView`
/// so the point-mapping and curve-smoothing math can be unit tested.
///
/// These are the exact code paths behind several past chart bugs — the empty
/// weekly chart, the line not freezing when the quota was exhausted, and the
/// Catmull-Rom curve bulging above the 100% line — so they get direct regression
/// coverage instead of living untestable inside a SwiftUI `View`.
enum ChartMath {

    /// Maps usage snapshots to chart-space points within the active window.
    ///
    /// - Snapshots before the window start (`elapsed < 0`) are skipped.
    /// - `x` is clamped to the window end and `y` to `[0, 1]`.
    /// - Iteration stops at the first snapshot that reached the cap
    ///   (`usage >= 1.0`) so the line freezes at that moment rather than drawing
    ///   a flat line to the window edge. Any stale post-cap snapshots are ignored.
    static func points(
        snapshots: [UsageSnapshot],
        resetDate: Date?,
        windowDuration: TimeInterval,
        width: CGFloat,
        usableHeight: CGFloat,
        topPadding: CGFloat
    ) -> [CGPoint] {
        guard let resetDate, !snapshots.isEmpty else { return [] }
        let windowStart = resetDate.addingTimeInterval(-windowDuration)

        var points: [CGPoint] = []
        for snapshot in snapshots {
            let elapsed = snapshot.timestamp.timeIntervalSince(windowStart)
            guard elapsed >= 0 else { continue }
            let xFraction = min(1, elapsed / windowDuration)
            let yFraction = max(0, min(1, snapshot.usage))
            points.append(CGPoint(x: width * xFraction, y: topPadding + usableHeight * (1 - yFraction)))
            if snapshot.usage >= 1.0 { break }
        }
        return points
    }

    /// Catmull-Rom control points for the segment `p1 → p2`, clamped to the
    /// segment's bounding box.
    ///
    /// The x clamp prevents overshoot across sparse-data gaps; the y clamp keeps
    /// the curve between the two samples. Without the y clamp a steep rise into a
    /// plateau bulges the curve above the plateau, rendering usage past the 100%
    /// line (the v1.3.8 fix).
    static func controlPoints(
        p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint,
        tension: CGFloat = 0.3
    ) -> (cp1: CGPoint, cp2: CGPoint) {
        let yLo = min(p1.y, p2.y)
        let yHi = max(p1.y, p2.y)
        let cp1 = CGPoint(
            x: max(p1.x, min(p2.x, p1.x + (p2.x - p0.x) * tension)),
            y: max(yLo, min(yHi, p1.y + (p2.y - p0.y) * tension))
        )
        let cp2 = CGPoint(
            x: max(p1.x, min(p2.x, p2.x - (p3.x - p1.x) * tension)),
            y: max(yLo, min(yHi, p2.y - (p3.y - p1.y) * tension))
        )
        return (cp1, cp2)
    }
}
