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
                        .fill(LinearGradient(colors: [DT.Colors.weeklyBlue.opacity(0.8), DT.Colors.weeklyBlue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * usage)
                        .animation(DT.Animation.progressFill, value: usage)
                }
            }
            .frame(height: 3)
            Text("\(Int(usage * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DT.Colors.weeklyBlue)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
