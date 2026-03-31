import SwiftUI

struct HeroView: View {
    let remaining: Double
    let lastUpdateDate: Date?

    private var isStale: Bool {
        guard let lastUpdate = lastUpdateDate else { return false }
        return Date().timeIntervalSince(lastUpdate) > 600
    }

    private var statusColor: Color {
        DT.Colors.statusColor(for: remaining)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(remaining * 100))")
                    .font(DT.Typography.heroPercent)
                    .foregroundStyle(statusColor)
                    .shadow(color: statusColor.opacity(0.5), radius: 8)
                Text("%")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .shadow(color: statusColor.opacity(0.5), radius: 8)
                if isStale {
                    Text(" (eski)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            Text("mesaj hakkın kaldı")
                .font(DT.Typography.heroSubtitle)
                .foregroundStyle(.secondary)
        }
    }
}
