import SwiftUI
import ServiceManagement

struct SystemTogglesView: View {
    @Bindable var notesManager: NotesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SISTEM")
                .font(DT.Typography.sectionTitle)
                .foregroundStyle(.quaternary)
                .kerning(0.8)
                .padding(.bottom, 8)
                .padding(.leading, 2)

            ToggleRow(label: "Acilista baslat", isOn: Binding(
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
                tooltip: "Limit sifirlaninca yeni oturumu erkenden baslatir."
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
    var tooltip: String? = nil
    @State private var isHovered = false

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(label).font(DT.Typography.label).foregroundStyle(.secondary)
                if let tooltip {
                    Text("?")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                        .help(tooltip)
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
