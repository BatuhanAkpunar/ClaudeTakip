import SwiftUI
// No LiquidGlass — fixed colors to avoid window-state vibrancy shift

// MARK: - Main View

struct MenuBarView: View {
    @Bindable var viewModel: MenuBarViewModel
    let onRefresh: () -> Void
    let onSignOut: () -> Void
    let onQuit: () -> Void
    var onStartSession: (() -> Void)?
    var onCheckUpdate: (() -> Void)?
    @State private var isRefreshing = false
    @State private var isQuitHovered = false
    @State private var isSettingsExpanded = false
    @State private var isInfoExpanded = false
    @State private var selectedChartTab: ChartTab = .session
    @State private var isChartExpanded = true
    @State private var valuesRevealed = false
    @State private var isCheckingUpdate = false

    enum ChartTab: String, CaseIterable { case session, weekly }

    /// Returns 0 when values haven't revealed yet, real value after.
    private func rv(_ value: Double) -> Double {
        valuesRevealed ? value : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if viewModel.notesManager.settings.aiRecommendation {
                            aiRecommendation
                        }

                        VStack(spacing: 8) {
                            sectionTitle(String(localized: "USAGE LIMITS", bundle: .app)) { refreshButton }
                            donutCards
                            ThemedDivider()
                            sonnetBar
                            if viewModel.extraUsageVisible {
                                ThemedDivider()
                                extraUsageBar
                            }
                        }
                        .padding(12)
                        .glassCard()

                        burnRateSection
                            .padding(12)
                            .glassCard()

                        chartSection
                            .padding(12)
                            .glassCard()
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .clipped()
                .opacity(isSettingsExpanded || isInfoExpanded ? 0 : 1)

                if isSettingsExpanded {
                    settingsPanel
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .transition(.opacity)
                }

                if isInfoExpanded {
                    infoPanel
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .transition(.opacity)
                }
            }

            ThemedDivider().padding(.horizontal, 12)

            headerBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: DT.Size.popoverWidth)
        .popoverBG()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.popoverRadius))
        .preferredColorScheme(colorScheme)
        .environment(\.locale, viewModel.appLocale)
        .onAppear {
            isSettingsExpanded = false
            isInfoExpanded = false
            valuesRevealed = false
            waitForDataThenReveal()
        }
        .onDisappear {
            valuesRevealed = false
        }
    }

    // MARK: - Value Reveal

    private func waitForDataThenReveal() {
        Task {
            // Wait until data is loaded
            while !viewModel.appState.hasLoadedUsage {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            // Small pause so the empty state is visible briefly
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) {
                valuesRevealed = true
            }
        }
    }


    // MARK: - Header Bar (Product header)

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left: product name + account/financial row
            VStack(alignment: .leading, spacing: 5) {
                Text("ClaudeTakip")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.7))

                HStack(spacing: 0) {
                    if let name = viewModel.appState.accountName {
                        HStack(spacing: 4) {
                            Text(name.truncatedBeforeApostropheS)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.70))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Button(action: { onSignOut() }) {
                                BI.boxArrowRight.view(size: 9)
                                    .foregroundStyle(.primary.opacity(0.70))
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help(Text("Sign out", bundle: .app))
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if let balanceText = viewModel.extraCurrentBalanceText {
                            HStack(spacing: 3) {
                                Image(systemName: "wallet.bifold.fill")
                                    .font(.system(size: 8))
                                Text(balanceText)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(.primary.opacity(0.70))
                        }

                        if let autoReload = viewModel.extraAutoReload {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 7.5, weight: .medium))
                                Text(autoReload ? String(localized: "Automatic", bundle: .app) : String(localized: "Manual", bundle: .app))
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(.primary.opacity(0.70))
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            // Right: action icons, vertically centered with left VStack
            HStack(spacing: 12) {
                Button(action: { viewModel.openStatusPage() }) {
                    statusCloudIcon
                }
                .buttonStyle(.plain)
                .help(viewModel.statusTooltip)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isInfoExpanded.toggle()
                        isSettingsExpanded = false
                    }
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isInfoExpanded ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .help(Text("Info", bundle: .app))

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isSettingsExpanded.toggle()
                        isInfoExpanded = false
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isSettingsExpanded ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .help(Text("Settings", bundle: .app))

                Button(action: { onQuit() }) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isQuitHovered ? Color.red.opacity(0.8) : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .onHover { isQuitHovered = $0 }
                .help(Text("Quit", bundle: .app))
            }
        }
    }

    // MARK: - Section Title

    private func sectionTitle(_ text: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DT.Colors.claudeAccent.opacity(0.85))
            Spacer()
            trailing()
        }
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        HStack(spacing: 4) {
            Text("Update:", bundle: .app)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.70))

            Button(action: {
                withAnimation(DT.Animation.refreshSpin) { isRefreshing = true }
                onRefresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isRefreshing = false }
            }) {
                BI.arrowClockwise.view(size: 9)
                    .foregroundStyle(.primary.opacity(0.70))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
            }
            .buttonStyle(.plain)
            .help(Text("Refresh", bundle: .app))

            Text(viewModel.lastUpdateText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.70))
        }
    }

    // MARK: - Donut Cards

    private var donutCards: some View {
        HStack(spacing: 10) {
            donutCard(
                usage: rv(viewModel.appState.sessionUsage),
                color: DT.Colors.statusColor(for: viewModel.appState.sessionRemaining),
                title: String(localized: "CURRENT SESSION (5 HRS)", bundle: .app),
                subtitle: viewModel.sessionRenewalText,
            )
            donutCard(
                usage: rv(viewModel.appState.weeklyUsage),
                color: DT.Colors.statusColor(for: 1.0 - viewModel.appState.weeklyUsage),
                title: String(localized: "WEEKLY (7 DAYS)", bundle: .app),
                subtitle: viewModel.weeklyRenewalText
            )
        }
    }

    private func donutCard(usage: Double, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            // Title centered
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.primary.opacity(0.50))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            // Donut centered
            ZStack {
                Circle()
                    .stroke(color.opacity(0.10), lineWidth: 7)
                // Glow arc (wide, soft)
                Circle()
                    .trim(from: 0, to: min(1, max(0, usage)))
                    .stroke(
                        color.opacity(0.18),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(DT.Animation.barFill, value: usage)
                // Main arc
                Circle()
                    .trim(from: 0, to: min(1, max(0, usage)))
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(DT.Animation.barFill, value: usage)

                VStack(spacing: -2) {
                    Text("\(Int(usage * 100))")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(color)
                    Text("%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color.opacity(0.7))
                }
            }
            .frame(width: 60, height: 60)

            Spacer(minLength: 0)

            // Subtitle: time on top, "resets in" below
            if !subtitle.isEmpty {
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "hourglass.bottomhalf.filled")
                            .font(.system(size: 8))
                        Text(subtitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    Text("resets in", bundle: .app)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.70))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .frame(height: 148)
    }

    // MARK: - Sonnet Bar

    private var sonnetBar: some View {
        HStack(spacing: 10) {
            Text("SONNET")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.primary.opacity(0.70))
                .frame(width: 48, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [DT.Colors.sonnetPurple.opacity(0.55), DT.Colors.sonnetPurple],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * max(0, min(1, rv(viewModel.sonnetBarProgress))))
                        .animation(DT.Animation.barFill, value: rv(viewModel.sonnetBarProgress))
                }
            }
            .frame(height: 10)
            .padding(.leading, 34)

            Text("\(Int(rv(viewModel.sonnetBarProgress) * 100))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(DT.Colors.sonnetPurple)
                .frame(width: 30, alignment: .leading)

            // Hourglass + single-line time
            let lines = viewModel.sonnetResetLines
            HStack(spacing: 4) {
                if !lines.0.isEmpty {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(lines.1.isEmpty ? lines.0 : "\(lines.0) \(lines.1)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.70))
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Extra Usage Bar

    private var extraUsageBar: some View {
        let unlimitedBlue = Color(nsColor: NSColor(
            name: nil,
            dynamicProvider: { $0.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.30, green: 0.56, blue: 0.85, alpha: 1.0)
                : NSColor(red: 0.106, green: 0.404, blue: 0.698, alpha: 1.0)
            }
        ))
        return HStack(spacing: 10) {
            // Left column: title + balance stacked, leading aligned
            VStack(alignment: .leading, spacing: 1) {
                Text("EXTRA", bundle: .app)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.primary.opacity(0.70))
                HStack(spacing: 3) {
                    Text(viewModel.extraUsedText)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.75))
                    if let balanceText = viewModel.extraCurrentBalanceText {
                        Text("/ \(balanceText)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.75))
                    } else if let limitText = viewModel.extraMonthlyLimitText {
                        Text(limitText)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.75))
                    } else if viewModel.isExtraUnlimited {
                        Text("/")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.75))
                        Image(systemName: "infinity")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(unlimitedBlue.opacity(0.85))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 48, alignment: .leading)

            if viewModel.isExtraUnlimited {
                HStack(spacing: 4) {
                    Image(systemName: "infinity")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(unlimitedBlue)
                    Text("Unlimited", bundle: .app)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(unlimitedBlue)
                    Text("Active", bundle: .app)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(unlimitedBlue.opacity(0.10), in: Capsule())
                .padding(.leading, 34)
                Spacer()
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                        if rv(viewModel.extraUsageProgress) > 0.01 {
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [DT.Colors.claudeAccent.opacity(0.55), DT.Colors.claudeAccent],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: geo.size.width * max(0, min(1, rv(viewModel.extraUsageProgress))))
                                .animation(DT.Animation.barFill, value: rv(viewModel.extraUsageProgress))
                        }
                    }
                }
                .frame(height: 10)
                .padding(.leading, 34)

                Text("\(Int(rv(viewModel.extraUsageProgress) * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DT.Colors.claudeAccent)
                    .frame(width: 30, alignment: .leading)
            }

            // Hourglass + single-line time
            let lines = viewModel.extraResetLines
            HStack(spacing: 4) {
                if !lines.0.isEmpty {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(lines.1.isEmpty ? lines.0 : "\(lines.0) \(lines.1)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.70))
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Burn Rate Section

    private var burnRateSection: some View {
        VStack(spacing: 10) {
            sectionTitle(String(localized: "USAGE RATE", bundle: .app)) {
                Text("Ideal = 1.0x", bundle: .app)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.70))
            }

            HStack(spacing: 10) {
                SpeedometerGaugeView(
                    rate: rv(viewModel.sessionRate),
                    title: String(localized: "Current Session (5 hrs)", bundle: .app),
                    badgeText: valuesRevealed ? viewModel.sessionGaugeBadgeText : "–",
                    badgeColor: viewModel.sessionGaugeBadgeColor,
                    deviationText: valuesRevealed ? viewModel.sessionDeviationText : "–",
                    limitReached: viewModel.appState.sessionUsage >= 1.0
                )
                SpeedometerGaugeView(
                    rate: rv(viewModel.weeklyRate),
                    title: String(localized: "Weekly (7 days)", bundle: .app),
                    badgeText: valuesRevealed ? viewModel.weeklyRateBadgeText : "–",
                    badgeColor: viewModel.weeklyRateBadgeColor,
                    deviationText: valuesRevealed ? viewModel.weeklyDeviationText : "–",
                    limitReached: viewModel.appState.weeklyUsage >= 1.0
                )
            }
        }
    }

    // MARK: - AI Recommendation

    private var aiRecommendation: some View {
        let strategy = viewModel.paceStrategy
        let accent = viewModel.paceStatusColor
        let unavailable = viewModel.appState.isAIUnavailable && viewModel.appState.aiPacingMessage == nil
        return Group {
            if unavailable {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("AI recommendations are currently unavailable", bundle: .app)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            } else if !strategy.isEmpty {
                Text(strategy)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.90))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(accent.opacity(0.25))
                            .offset(x: 6, y: 6)
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.70), accent.opacity(0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: accent.opacity(0.30), radius: 10, x: 0, y: 3)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            }
        }
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Text("USAGE HISTORY", bundle: .app)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(DT.Colors.claudeAccent.opacity(0.85))
                    Image(systemName: isChartExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DT.Colors.claudeAccent.opacity(0.6))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isChartExpanded {
                        isChartExpanded = false
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isChartExpanded = true
                        }
                    }
                }
                Spacer()
                if isChartExpanded {
                    chartTabPicker
                }
            }

            if isChartExpanded {
                switch selectedChartTab {
                case .session:
                    DetailedChartView(
                        snapshots: valuesRevealed ? viewModel.appState.usageHistory : [],
                        resetDate: viewModel.appState.sessionResetDate,
                        windowDuration: TimingConstants.sessionWindowDuration,
                        color: DT.Colors.statusGreen,
                        xLabels: viewModel.sessionHourLabels,
                        predictedDepletionDate: viewModel.sessionRate > 1.0 ? viewModel.predictedDepletionDate : nil
                    )
                case .weekly:
                    DetailedChartView(
                        snapshots: valuesRevealed ? viewModel.appState.weeklyUsageHistory : [],
                        resetDate: viewModel.appState.weeklyResetDate,
                        windowDuration: TimingConstants.weeklyWindowDuration,
                        color: DT.Colors.statusGreen,
                        xLabels: viewModel.weeklyDayLabels,
                        predictedDepletionDate: nil
                    )
                }
            }
        }
    }

    private var chartTabPicker: some View {
        let activeColor = Color.primary.opacity(0.7)
        let inactiveColor = Color.primary.opacity(0.4)
        let activeBg = DT.Colors.claudeAccent.opacity(0.15)

        return HStack(spacing: 2) {
            ForEach(ChartTab.allCases, id: \.self) { tab in
                let isSelected = selectedChartTab == tab
                Button(action: { selectedChartTab = tab }) {
                    Text(tab == .session ? String(localized: "Current Session", bundle: .app) : String(localized: "Weekly", bundle: .app))
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? activeColor : inactiveColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 0)
                        .background(
                            isSelected ? activeBg : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "globe",
                title: String(localized: "Language", bundle: .app),
                subtitle: String(localized: "App language", bundle: .app)
            ) {
                Picker("", selection: Binding(
                    get: { viewModel.notesManager.settings.language ?? "system" },
                    set: { v in
                        let lang = v == "system" ? nil : v
                        viewModel.notesManager.updateSettings { $0.language = lang }
                        LanguageManager.apply(lang)
                    }
                )) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("Türkçe").tag("tr")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Italiano").tag("it")
                    Text("Nederlands").tag("nl")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("简体中文").tag("zh-Hans")
                    Text("繁體中文").tag("zh-Hant")
                    Text("Русский").tag("ru")
                    Text("العربية").tag("ar")
                    Text("Português (BR)").tag("pt-BR")
                }
                .labelsHidden()
                .frame(width: 120)
            }

            settingDivider

            settingRow(
                icon: "moon.stars",
                title: String(localized: "Appearance", bundle: .app),
                subtitle: String(localized: "Choose between light and dark theme", bundle: .app)
            ) {
                ThemeToggle(isDark: Binding(
                    get: { viewModel.notesManager.settings.darkMode ?? false },
                    set: { v in viewModel.notesManager.updateSettings { $0.darkMode = v } }
                ))
            }

            settingDivider

            settingRow(
                icon: "power",
                title: String(localized: "Launch at Login", bundle: .app),
                subtitle: String(localized: "Starts the app when your Mac boots up", bundle: .app)
            ) {
                PillToggle(isOn: Binding(
                    get: { viewModel.notesManager.settings.launchAtLogin },
                    set: { v in viewModel.notesManager.updateSettings { $0.launchAtLogin = v } }
                ))
            }

            settingDivider

            settingRow(
                icon: "arrow.triangle.2.circlepath",
                title: String(localized: "Auto Session", bundle: .app),
                subtitle: String(localized: "Starts a new session after 5 hours to avoid waiting at limit resets (while app is open)", bundle: .app)
            ) {
                PillToggle(isOn: Binding(
                    get: { viewModel.notesManager.settings.autoSession },
                    set: { v in
                        viewModel.notesManager.updateSettings { $0.autoSession = v }
                        if v { onStartSession?() }
                    }
                ))
            }

            settingDivider

            settingRow(
                icon: "arrow.down.circle",
                title: String(localized: "Auto Update", bundle: .app),
                subtitle: String(localized: "Downloads and installs updates in the background", bundle: .app)
            ) {
                PillToggle(isOn: Binding(
                    get: { viewModel.notesManager.settings.autoUpdate },
                    set: { v in viewModel.notesManager.updateSettings { $0.autoUpdate = v } }
                ))
            }

            settingDivider

            settingRow(
                icon: "sparkles",
                title: String(localized: "AI Recommendation", bundle: .app),
                subtitle: String(localized: "AI-powered usage reports and recommendations", bundle: .app)
            ) {
                PillToggle(isOn: Binding(
                    get: { viewModel.notesManager.settings.aiRecommendation },
                    set: { v in viewModel.notesManager.updateSettings { $0.aiRecommendation = v } }
                ))
            }
        }
        .glassCard()
    }

    private var settingDivider: some View {
        ThemedDivider().padding(.leading, 44)
    }

    private func settingRow<ToggleContent: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder toggle: () -> ToggleContent
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.55))
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.50))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            toggle()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Info Panel

    private var infoPanel: some View {
        VStack(spacing: 0) {
            // Logo + app name header
            VStack(spacing: 8) {
                Image("ClaudeLogo")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                VStack(spacing: 3) {
                    Text("ClaudeTakip")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text("v\(appVersion)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            ThemedDivider()

            infoLinkRow(
                icon: "globe",
                title: String(localized: "Website", bundle: .app),
                subtitle: "claudetakip.vercel.app"
            ) {
                openURL("https://claudetakip.vercel.app")
            }

            infoDivider

            infoLinkRow(
                icon: "shield.checkered",
                title: String(localized: "Privacy Policy", bundle: .app),
                subtitle: "claudetakip.vercel.app/privacy"
            ) {
                openURL("https://claudetakip.vercel.app/privacy")
            }

            infoDivider

            infoLinkRow(
                icon: "person.fill",
                title: String(localized: "Developer", bundle: .app),
                subtitle: "Batuhan Akpunar"
            ) {
                openURL("https://www.linkedin.com/in/batuhanakpunar/")
            }

            infoDivider

            HStack {
                Text("Update", bundle: .app)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.65))

                Spacer(minLength: 4)

                Button(action: {
                    guard !isCheckingUpdate else { return }
                    isCheckingUpdate = true
                    onCheckUpdate?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        isCheckingUpdate = false
                    }
                }) {
                    Group {
                        if isCheckingUpdate {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Text("Check", bundle: .app)
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .foregroundStyle(DT.Colors.claudeAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DT.Colors.claudeAccent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isCheckingUpdate)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .glassCard()
    }

    private var infoDivider: some View {
        ThemedDivider().padding(.leading, 44)
    }

    private func infoLinkRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.55))
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.50))
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Status Cloud Icon

    private var statusCloudIcon: some View {
        Group {
            switch viewModel.appState.connectionStatus {
            case .connected:
                switch viewModel.appState.claudeSystemStatus {
                case .operational:
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DT.Colors.statusGreen)
                case .degraded, .major, .maintenance:
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DT.Colors.statusRed)
                }
            case .disconnected:
                Image(systemName: "cloud.slash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.gray)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DT.Colors.statusRed)
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private var colorScheme: ColorScheme? {
        switch viewModel.notesManager.settings.darkMode {
        case true: .dark
        case false: .light
        case nil: nil
        }
    }
}

// MARK: - Theme Toggle (Sun / Moon)

private struct ThemeToggle: View {
    @Binding var isDark: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isDark.toggle()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(isDark
                          ? Color.white.opacity(0.08)
                          : Color.orange.opacity(0.12))
                    .frame(width: 44, height: 24)
                    .overlay(
                        Capsule().strokeBorder(
                            isDark ? Color.white.opacity(0.10) : Color.orange.opacity(0.15),
                            lineWidth: 0.5
                        )
                    )

                HStack {
                    if isDark { Spacer() }
                    ZStack {
                        Circle()
                            .fill(isDark ? Color.indigo : Color.orange)
                            .frame(width: 18, height: 18)
                        Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    if !isDark { Spacer() }
                }
                .padding(.horizontal, 3)
                .frame(width: 44, height: 24)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill Toggle

private struct PillToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isOn.toggle()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(isOn
                          ? DT.Colors.claudeAccent.opacity(0.15)
                          : Color.primary.opacity(0.06))
                    .frame(width: 38, height: 22)
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? DT.Colors.claudeAccent.opacity(0.25) : Color.primary.opacity(0.08),
                            lineWidth: 0.5
                        )
                    )

                HStack {
                    if isOn { Spacer() }
                    Circle()
                        .fill(isOn ? DT.Colors.claudeAccent : Color.primary.opacity(0.20))
                        .frame(width: 16, height: 16)
                    if !isOn { Spacer() }
                }
                .padding(.horizontal, 3)
                .frame(width: 38, height: 22)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - String Helpers

private extension String {
    var truncatedBeforeApostropheS: String {
        if let range = range(of: "\u{2019}s ", options: .literal) ?? range(of: "'s ", options: .literal) {
            return String(self[..<range.lowerBound])
        }
        return self
    }
}
