import SwiftUI
import ServiceManagement

struct SystemTogglesView: View {
    @Bindable var notesManager: NotesManager

    @State private var showAutoSessionTip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SİSTEM")
                .font(DT.Typography.sectionTitle)
                .foregroundStyle(.quaternary)
                .kerning(0.8)
                .padding(.bottom, 8)
                .padding(.leading, 2)

            ToggleRow(label: "Açılışta başlat", isOn: Binding(
                get: { notesManager.settings.launchAtLogin },
                set: { newValue in
                    notesManager.updateSettings { $0.launchAtLogin = newValue }
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }
            ))

            ToggleRow(
                label: "Otomatik oturum",
                isOn: Binding(
                    get: { notesManager.settings.autoSession },
                    set: { newValue in notesManager.updateSettings { $0.autoSession = newValue } }
                ),
                showTip: $showAutoSessionTip,
                tipTitle: "Otomatik oturum",
                tipBody: "Limit sıfırlanınca kısa bir mesaj gönderip hemen siler. Bu, yeni 5 saatlik pencereyi erkenden başlatır.\n\nÖrnek: Saat 10:00'da başladıysan normalde 15:00'da sıfırlanır. Ama o sırada mesaj atmazsan sonraki pencere 17:00'a kayar. Bu özellik açıksa otomatik başlatılır."
            )

            ThemeRow(darkMode: Binding(
                get: { notesManager.settings.darkMode },
                set: { newValue in notesManager.updateSettings { $0.darkMode = newValue } }
            ))
        }
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    @Binding var showTip: Bool
    var tipTitle: String = ""
    var tipBody: String = ""
    @State private var isHovered = false

    init(label: String, isOn: Binding<Bool>, showTip: Binding<Bool> = .constant(false), tipTitle: String = "", tipBody: String = "") {
        self.label = label
        self._isOn = isOn
        self._showTip = showTip
        self.tipTitle = tipTitle
        self.tipBody = tipBody
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(label).font(DT.Typography.label).foregroundStyle(.secondary)
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
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.vertical, DT.Spacing.toggleRowPaddingV)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: DT.Radius.iconButton).fill(isHovered ? DT.Colors.hoverHighlight : .clear))
        .onHover { isHovered = $0 }
    }
}

struct ThemeRow: View {
    @Binding var darkMode: Bool?

    var body: some View {
        HStack {
            Text("Tema").font(DT.Typography.label).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $darkMode) {
                Image(systemName: "moon.fill").tag(Bool?(true))
                Image(systemName: "gear").tag(Bool?(nil))
                Image(systemName: "sun.max.fill").tag(Bool?(false))
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(.vertical, DT.Spacing.toggleRowPaddingV)
        .padding(.horizontal, 2)
    }
}
