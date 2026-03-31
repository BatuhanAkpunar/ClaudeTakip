import SwiftUI

struct WeeklyBarView: View {
    let usage: Double

    var body: some View {
        HStack(spacing: 10) {
            Text("Haftalik")
                .font(DT.Typography.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(DT.Colors.trackBackground)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [DT.Colors.weeklyPurple.opacity(0.8), DT.Colors.weeklyPurple], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * usage)
                        .shadow(color: DT.Colors.glowPurple, radius: 3)
                        .animation(DT.Animation.progressFill, value: usage)
                }
            }
            .frame(height: 3)
            Text("\(Int(usage * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DT.Colors.weeklyPurple)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
