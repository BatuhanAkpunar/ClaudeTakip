import SwiftUI

struct PopoverHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 540 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MenuBarView: View {
    @Bindable var viewModel: MenuBarViewModel
    let onRefresh: () -> Void
    let onSignOut: () -> Void
    let onQuit: () -> Void
    var onHeightChange: ((CGFloat) -> Void)?
    @State private var isRefreshing = false

    var body: some View {
        HStack(spacing: 0) {
            mainContent
                .frame(width: DT.Size.popoverWidth)

            if viewModel.isNotesOpen {
                Divider()
                    .opacity(0.3)
                NotesPanelView(notesManager: viewModel.notesManager)
                    .frame(width: DT.Size.notesPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial)
        .animation(DT.Animation.notesSlide, value: viewModel.isNotesOpen)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PopoverHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(PopoverHeightKey.self) { height in
            onHeightChange?(height)
        }
        .preferredColorScheme(colorScheme)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 18)

            HeroView(remaining: viewModel.appState.sessionRemaining, lastUpdateDate: viewModel.appState.lastUpdateDate)
                .padding(.bottom, 12)

            ProgressBarView(
                remaining: viewModel.appState.sessionRemaining,
                timeElapsedFraction: viewModel.timeElapsedFraction
            )
            .padding(.bottom, 18)

            HStack(spacing: DT.Spacing.itemGap) {
                InfoCardView(value: viewModel.resetTimeText, label: "S\u{0131}f\u{0131}rlama")
                InfoCardView(
                    value: viewModel.paceStatusText,
                    label: "H\u{0131}z",
                    valueColor: viewModel.paceStatusColor
                )
                InfoCardView(value: viewModel.lastUpdateText, label: "G\u{00FC}ncelleme")
            }
            .padding(.bottom, 12)

            WeeklyBarView(usage: viewModel.appState.weeklyUsage)
                .padding(.bottom, DT.Spacing.sectionGap)

            sectionDivider

            PacingTogglesView(notesManager: viewModel.notesManager)
                .padding(.vertical, 4)

            sectionDivider

            SystemTogglesView(notesManager: viewModel.notesManager)
                .padding(.vertical, 4)

            sectionDivider

            footer
                .padding(.top, DT.Spacing.sectionGap)
        }
        .padding(DT.Spacing.popoverPadding)
    }

    private var header: some View {
        HStack {
            Button(action: { viewModel.openStatusPage() }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.connectionDotColor)
                        .frame(width: DT.Size.statusDotSize, height: DT.Size.statusDotSize)
                        .shadow(color: viewModel.connectionDotColor.opacity(0.6), radius: 4)
                    Text(viewModel.connectionStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Button(action: { viewModel.toggleNotes() }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13))
                            .foregroundStyle(viewModel.isNotesOpen ? .primary : .secondary)
                            .frame(width: DT.Size.iconButtonSize, height: DT.Size.iconButtonSize)
                            .background(
                                RoundedRectangle(cornerRadius: DT.Radius.iconButton)
                                    .fill(viewModel.isNotesOpen ? DT.Colors.hoverHighlight : .clear)
                            )
                        if viewModel.noteCount > 0 {
                            Text("\(viewModel.noteCount)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(DT.Colors.cardBackground, in: Capsule())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(DT.Animation.refreshSpin) {
                        isRefreshing = true
                    }
                    onRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isRefreshing = false
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .frame(width: DT.Size.iconButtonSize, height: DT.Size.iconButtonSize)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Hesaptan \u{00E7}\u{0131}k") { onSignOut() }
                .buttonStyle(FooterButtonStyle(isDestructive: true))
            Spacer()
            Button("Kapat") { onQuit() }
                .buttonStyle(FooterButtonStyle(isDestructive: false))
        }
    }

    private var sectionDivider: some View {
        Divider()
            .opacity(0.3)
    }

    private var colorScheme: ColorScheme? {
        switch viewModel.notesManager.settings.darkMode {
        case true: .dark
        case false: .light
        case nil: nil
        }
    }
}

struct FooterButtonStyle: ButtonStyle {
    let isDestructive: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DT.Typography.footerAction)
            .foregroundStyle(isHovered && isDestructive ? Color.red : Color.primary.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.iconButton)
                    .fill(isHovered ? (isDestructive ? Color.red.opacity(0.08) : DT.Colors.hoverHighlight) : .clear)
            )
            .onHover { isHovered = $0 }
    }
}
