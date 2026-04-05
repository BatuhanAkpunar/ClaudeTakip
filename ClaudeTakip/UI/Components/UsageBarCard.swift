import SwiftUI

struct UsageBarCard: View {
    let title: String
    let progress: Double
    let color: Color
    let valueText: String
    let trailingText: String?

    init(
        title: String,
        progress: Double,
        color: Color,
        valueText: String,
        trailingText: String? = nil
    ) {
        self.title = title
        self.progress = progress
        self.color = color
        self.valueText = valueText
        self.trailingText = trailingText
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.primary.opacity(0.70))

                Spacer()

                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))

                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                        .animation(DT.Animation.barFill, value: progress)
                }
            }
            .frame(height: 10)

            if let trailingText {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9.5))
                    Text(trailingText)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.primary.opacity(0.70))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }
}
