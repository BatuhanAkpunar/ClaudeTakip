import SwiftUI
// Uses .glassCard() from DesignTokens

struct LoadingView: View {
    @State private var pulsing = false

    private let skeletonColor = Color.primary.opacity(0.12)
    private let pulseRange: (Double, Double) = (0.4, 1.0)

    var body: some View {
        VStack(spacing: 10) {
            // AI recommendation skeleton
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .fill(skeletonColor)
                .frame(height: 52)

            // Quota status card
            VStack(spacing: 8) {
                // Title row
                HStack {
                    pill(width: 100)
                    Spacer()
                    pill(width: 120)
                }

                // Two donut placeholders
                HStack(spacing: 10) {
                    donutPlaceholder
                    donutPlaceholder
                }

                Rectangle().fill(skeletonColor).frame(height: 0.5)

                // Sonnet bar
                HStack(spacing: 10) {
                    pill(width: 48)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(skeletonColor)
                        .frame(height: 10)
                    pill(width: 30)
                }
                .padding(.vertical, 6)
            }
            .padding(12)
            .glassCard()

            // Burn rate card
            VStack(spacing: 10) {
                HStack {
                    pill(width: 110)
                    Spacer()
                    pill(width: 80)
                }
                HStack(spacing: 10) {
                    gaugePlaceholder
                    gaugePlaceholder
                }
            }
            .padding(12)
            .glassCard()

            // Chart card
            VStack(spacing: 10) {
                HStack {
                    pill(width: 120)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 5)
                    .fill(skeletonColor)
                    .frame(height: 16)
            }
            .padding(12)
            .glassCard()

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(pulsing ? pulseRange.1 : pulseRange.0)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                pulsing = true
            }
        }
    }

    // MARK: - Primitives

    private func pill(width: CGFloat) -> some View {
        Capsule()
            .fill(skeletonColor)
            .frame(width: width, height: 10)
    }

    // MARK: - Donut Placeholder

    private var donutPlaceholder: some View {
        VStack(spacing: 6) {
            pill(width: 90)
            Spacer(minLength: 0)
            Circle()
                .stroke(skeletonColor, lineWidth: 7)
                .frame(width: 60, height: 60)
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                pill(width: 70)
                pill(width: 90)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .frame(height: 148)
    }

    // MARK: - Gauge Placeholder

    private var gaugePlaceholder: some View {
        VStack(spacing: 6) {
            pill(width: 100)
            // Half-circle arc
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let radius = min(w / 2 - 6, h - 6)
                let center = CGPoint(x: w / 2, y: h * 0.92)
                Path { path in
                    path.addArc(
                        center: center, radius: radius,
                        startAngle: .degrees(180), endAngle: .degrees(0),
                        clockwise: false
                    )
                }
                .stroke(skeletonColor, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            }
            .frame(height: 44)
            Spacer(minLength: 0)
            pill(width: 60)
            Capsule()
                .fill(skeletonColor)
                .frame(width: 70, height: 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(height: 122)
    }
}
