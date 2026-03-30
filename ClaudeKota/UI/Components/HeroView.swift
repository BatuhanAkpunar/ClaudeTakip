import SwiftUI

struct HeroView: View {
    let remaining: Double
    let lastUpdateDate: Date?

    private var isStale: Bool {
        guard let lastUpdate = lastUpdateDate else { return false }
        return Date().timeIntervalSince(lastUpdate) > 600
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(remaining * 100))")
                    .font(DT.Typography.heroPercent)
                    .foregroundStyle(DT.Colors.statusColor(for: remaining))
                Text("%")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(DT.Colors.statusColor(for: remaining))
                if isStale {
                    Text(" (eski)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            Text("mesaj hakkin kaldi")
                .font(DT.Typography.label)
                .foregroundStyle(.secondary)
        }
    }
}
