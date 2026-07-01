import Testing
import Foundation
import CoreGraphics
@testable import ClaudeTakip

/// Regression coverage for the chart geometry that has caused several shipped
/// bugs: the empty weekly chart, the line not freezing at the cap, and the
/// Catmull-Rom curve overshooting the 100% line.
@Suite struct ChartMathTests {

    // Fixed window so point math is exact. reset at ref, window = 300s, so
    // windowStart = ref - 300. width=100, usableHeight=100, topPadding=0 →
    //   x = 100 * min(1, elapsed/300)
    //   y = 100 * (1 - clamp(usage, 0, 1))
    private let ref = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let window: TimeInterval = 300

    private func snap(_ offsetFromStart: TimeInterval, _ usage: Double) -> UsageSnapshot {
        let windowStart = ref.addingTimeInterval(-window)
        return UsageSnapshot(timestamp: windowStart.addingTimeInterval(offsetFromStart), usage: usage)
    }

    private func points(_ snaps: [UsageSnapshot]) -> [CGPoint] {
        ChartMath.points(
            snapshots: snaps, resetDate: ref, windowDuration: window,
            width: 100, usableHeight: 100, topPadding: 0
        )
    }

    // MARK: - points()

    @Test func emptySnapshotsYieldNoPoints() {
        #expect(points([]).isEmpty)
    }

    @Test func nilResetDateYieldsNoPoints() {
        let result = ChartMath.points(
            snapshots: [snap(60, 0.5)], resetDate: nil, windowDuration: window,
            width: 100, usableHeight: 100, topPadding: 0
        )
        #expect(result.isEmpty)
    }

    @Test func snapshotsBeforeWindowStartAreSkipped() {
        // -10s is before the window; +150s maps to x=50, usage .5 → y=50
        let result = points([snap(-10, 0.9), snap(150, 0.5)])
        #expect(result.count == 1)
        #expect(abs(result[0].x - 50) < 0.001)
        #expect(abs(result[0].y - 50) < 0.001)
    }

    @Test func lineFreezesAtFirstCappedSnapshot() {
        // 0.5 → 1.0 (cap) → 0.3 (stale post-cap). Must stop after the cap.
        let result = points([snap(60, 0.5), snap(120, 1.0), snap(180, 0.3)])
        #expect(result.count == 2)
        // Last point is the cap: usage 1.0 → y = 0 (top of chart)
        #expect(abs(result.last!.y - 0) < 0.001)
    }

    @Test func xIsClampedToWindowEnd() {
        // elapsed 400 > window 300 → xFraction clamped to 1 → x = width
        let result = points([snap(400, 0.5)])
        #expect(result.count == 1)
        #expect(abs(result[0].x - 100) < 0.001)
    }

    @Test func usageAboveOneClampsYToTopAndFreezes() {
        // API occasionally returns >100%. y clamps to 0 and iteration stops.
        let result = points([snap(60, 1.15), snap(120, 0.4)])
        #expect(result.count == 1)
        #expect(abs(result[0].y - 0) < 0.001)
    }

    @Test func negativeUsageClampsYToBottom() {
        let result = points([snap(60, -0.5)])
        #expect(result.count == 1)
        #expect(abs(result[0].y - 100) < 0.001)
    }

    // MARK: - controlPoints() — overshoot regression

    @Test func controlPointYStaysWithinSegmentBounds() {
        let p0 = CGPoint(x: 0, y: 80)
        let p1 = CGPoint(x: 10, y: 80)
        let p2 = CGPoint(x: 20, y: 0)
        let p3 = CGPoint(x: 30, y: 0)
        let cp = ChartMath.controlPoints(p0: p0, p1: p1, p2: p2, p3: p3)
        let lo = min(p1.y, p2.y), hi = max(p1.y, p2.y)
        #expect(cp.cp1.y >= lo && cp.cp1.y <= hi)
        #expect(cp.cp2.y >= lo && cp.cp2.y <= hi)
    }

    /// The exact overshoot bug: a plateau segment (p1,p2 both at y=0, the 100%
    /// line) with a lower neighbor. Un-clamped, cp1.y computes to -24 — *above*
    /// the 100% line. The clamp must pin it to the plateau (y=0).
    @Test func plateauControlPointDoesNotRiseAboveCap() {
        let cp = ChartMath.controlPoints(
            p0: CGPoint(x: 0, y: 80),
            p1: CGPoint(x: 10, y: 0),
            p2: CGPoint(x: 20, y: 0),
            p3: CGPoint(x: 30, y: 0)
        )
        #expect(cp.cp1.y == 0, "control point must not rise above the plateau (100% line)")
        #expect(cp.cp2.y == 0)
    }

    @Test func controlPointXStaysWithinSegment() {
        let cp = ChartMath.controlPoints(
            p0: CGPoint(x: 0, y: 50),
            p1: CGPoint(x: 40, y: 40),
            p2: CGPoint(x: 60, y: 30),
            p3: CGPoint(x: 200, y: 20) // far-away neighbor would overshoot x
        )
        #expect(cp.cp1.x >= 40 && cp.cp1.x <= 60)
        #expect(cp.cp2.x >= 40 && cp.cp2.x <= 60)
    }
}
