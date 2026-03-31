import SwiftUI

struct InfoCardView: View {
    let value: String
    let label: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DT.Typography.cardValue)
                .foregroundStyle(valueColor)
            Text(label)
                .font(DT.Typography.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DT.Spacing.cardPaddingH)
        .padding(.vertical, DT.Spacing.cardPaddingV)
        .background(DT.Colors.cardBackground, in: RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).strokeBorder(DT.Colors.cardBorder, lineWidth: 0.5))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).strokeBorder(valueColor.opacity(0.2), lineWidth: 0.5))
    }
}
