import SwiftUI

struct PacingTogglesView: View {
    @Bindable var notesManager: NotesManager

    @State private var showFastConsumptionTip = false
    @State private var showCriticalThresholdTip = false
    @State private var showResetTip = false
    @State private var showSoundTip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AKILLI UYARILAR")
                .font(DT.Typography.sectionTitle)
                .foregroundStyle(.quaternary)
                .kerning(0.8)
                .padding(.bottom, 8)
                .padding(.leading, 2)
            CheckboxRow(
                label: "Hızlı tüketim uyarısı",
                isChecked: Binding(
                    get: { notesManager.settings.fastConsumptionAlert },
                    set: { newValue in notesManager.updateSettings { $0.fastConsumptionAlert = newValue } }
                ),
                showTip: $showFastConsumptionTip,
                tipTitle: "Hızlı tüketim uyarısı",
                tipBody: "Mesaj gönderme hızın idealin üstüne çıkınca uyarır. Örnek: 5 saatlik limitin 2 saatte %60'ını kullandıysan uyarı gelir. Oturum başına en fazla 2 kez."
            )
            CheckboxRow(
                label: "Kritik eşik uyarısı",
                isChecked: Binding(
                    get: { notesManager.settings.criticalThresholdAlert },
                    set: { newValue in notesManager.updateSettings { $0.criticalThresholdAlert = newValue } }
                ),
                showTip: $showCriticalThresholdTip,
                tipTitle: "Kritik eşik uyarısı",
                tipBody: "Kalan hakkın %10'un altına düşünce bir kez uyarır. Örnek: 100 mesajdan 90'ını kullandıysan bildirim alırsın."
            )
            CheckboxRow(
                label: "Sıfırlama bildirimi",
                isChecked: Binding(
                    get: { notesManager.settings.resetNotification },
                    set: { newValue in notesManager.updateSettings { $0.resetNotification = newValue } }
                ),
                showTip: $showResetTip,
                tipTitle: "Sıfırlama bildirimi",
                tipBody: "5 saatlik pencere sıfırlanınca bildirir. Örnek: Saat 10:00'da başladıysan 15:00'da 'Hakkın yenilendi!' bildirimi gelir."
            )
            CheckboxRow(
                label: "Sesli bildirim",
                isChecked: Binding(
                    get: { notesManager.settings.soundEnabled },
                    set: { newValue in notesManager.updateSettings { $0.soundEnabled = newValue } }
                ),
                showTip: $showSoundTip,
                tipTitle: "Sesli bildirim",
                tipBody: "Yukarıdaki uyarılar geldiğinde kısa bir ses çalar."
            )
        }
    }
}

struct CheckboxRow: View {
    let label: String
    @Binding var isChecked: Bool
    @Binding var showTip: Bool
    var tipTitle: String = ""
    var tipBody: String = ""
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
            if !tipBody.isEmpty {
                Button(action: { showTip.toggle() }) {
                    Text("?")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTip, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tipTitle)
                            .font(DT.Typography.tooltipTitle)
                        Text(tipBody)
                            .font(DT.Typography.tooltipBody)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: 220)
                }
            }
            Spacer()
        }
        .padding(.vertical, DT.Spacing.toggleRowPaddingV)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: DT.Radius.iconButton).fill(isHovered ? DT.Colors.hoverHighlight : .clear))
        .onHover { isHovered = $0 }
        .onTapGesture { isChecked.toggle() }
    }
}
