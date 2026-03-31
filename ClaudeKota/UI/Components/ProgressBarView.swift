import SwiftUI

struct ProgressBarView: View {
    let remaining: Double
    let timeElapsedFraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DT.Size.progressBarHeight / 2)
                    .fill(DT.Colors.trackBackground)
                RoundedRectangle(cornerRadius: DT.Size.progressBarHeight / 2)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0, min(1, remaining)))
                    .shadow(color: fillColor.opacity(0.4), radius: 4)
                    .animation(DT.Animation.progressFill, value: remaining)
                if timeElapsedFraction > 0, timeElapsedFraction < 1 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(DT.Colors.weeklyPurple)
                        .frame(width: DT.Size.timeMarkerWidth, height: DT.Size.timeMarkerHeight)
                        .offset(x: geo.size.width * timeElapsedFraction - 1, y: -2)
                }
            }
        }
        .frame(height: DT.Size.progressBarHeight)
    }

    private var fillColor: Color {
        DT.Colors.statusColor(for: remaining)
    }

    private var gradientColors: [Color] {
        return [fillColor.opacity(0.8), fillColor]
    }
}
