import SwiftUI

struct PacingTogglesView: View {
    @Bindable var notesManager: NotesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AKILLI UYARILAR")
                .font(DT.Typography.sectionTitle)
                .foregroundStyle(.quaternary)
                .kerning(0.8)
                .padding(.bottom, 8)
                .padding(.leading, 2)
            CheckboxRow(label: "Hizli tuketim uyarisi", isChecked: Binding(
                get: { notesManager.settings.fastConsumptionAlert },
                set: { newValue in notesManager.updateSettings { $0.fastConsumptionAlert = newValue } }
            ))
            CheckboxRow(label: "Kritik esik uyarisi", isChecked: Binding(
                get: { notesManager.settings.criticalThresholdAlert },
                set: { newValue in notesManager.updateSettings { $0.criticalThresholdAlert = newValue } }
            ))
            CheckboxRow(label: "Sifirlama bildirimi", isChecked: Binding(
                get: { notesManager.settings.resetNotification },
                set: { newValue in notesManager.updateSettings { $0.resetNotification = newValue } }
            ))
            CheckboxRow(label: "Sesli bildirim", isChecked: Binding(
                get: { notesManager.settings.soundEnabled },
                set: { newValue in notesManager.updateSettings { $0.soundEnabled = newValue } }
            ))
        }
    }
}

struct CheckboxRow: View {
    let label: String
    @Binding var isChecked: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: DT.Radius.checkbox)
                .fill(isChecked ? DT.Colors.statusGreen : .clear)
                .overlay(
                    Group {
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                        } else {
                            RoundedRectangle(cornerRadius: DT.Radius.checkbox)
                                .strokeBorder(.quaternary, lineWidth: 1.5)
                        }
                    }
                )
                .frame(width: DT.Size.checkboxSize, height: DT.Size.checkboxSize)
            Text(label)
                .font(DT.Typography.label)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, DT.Spacing.toggleRowPaddingV)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: DT.Radius.iconButton).fill(isHovered ? DT.Colors.hoverHighlight : .clear))
        .onHover { isHovered = $0 }
        .onTapGesture { isChecked.toggle() }
    }
}
