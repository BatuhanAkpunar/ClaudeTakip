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
    /// Snapshot harness only: skip the reveal animation so offscreen renders
    /// show real values (the reveal Task doesn't drain in a pumped run loop).
    var revealImmediately: Bool = false
    /// Snapshot harness only: force the USAGE LIMITS pager to a page.
    var limitsPageForSnapshot: Int? = nil
    /// Snapshot harness only: render the chart card collapsed (sparkline peek).
    var collapseChartForSnapshot: Bool = false
    @State private var limitsPage: Int = 0
    @State private var limitsDragOffset: CGFloat = 0
    @State private var isRefreshing = false
    @State private var isRefreshHovered = false
    @State private var isSettingsExpanded = false
    @State private var isInfoExpanded = false
    @State private var isAccountExpanded = false
    @State private var selectedChartTab: ChartTab = .session
    @State private var isChartExpanded = true
    @State private var valuesRevealed = false
    @State private var isCheckingUpdate = false
    /// Unified entrance system: false while elements sit at opacity 0 / y+8
    /// with empty fills; flipping to true plays the staggered load-in.
    @State private var entered = false
    /// Gates the entrance animations so the reset to the hidden state is
    /// instant (nil animation) and only the reveal is animated.
    @State private var entranceAnimated = false
    /// Chart draw-on state — the USAGE HISTORY curve draws on from zero
    /// (left → right) on reveal and on every session/weekly tab switch.
    @State private var chartEntered = false
    @State private var chartAnimated = false
    @Environment(\.colorScheme) private var envColorScheme

    enum ChartTab: String, CaseIterable { case session, weekly }

    /// Returns 0 when values haven't revealed yet, real value after.
    private func rv(_ value: Double) -> Double {
        valuesRevealed ? value : 0
    }

    // MARK: - Unified Entrance System (one load-in for all pager pages)

    /// Fill amount for arcs/bars/rings: 0 before entrance, real value after.
    private func entranceFill(_ value: Double) -> Double {
        entered ? value : 0
    }

    /// Fade+rise timing for an element at stagger `slot` (~60 ms apart).
    private func entranceAnimation(_ slot: Int) -> Animation? {
        entranceAnimated ? .easeOut(duration: 0.45).delay(Double(slot) * 0.06) : nil
    }

    /// Fill timing for arcs/bars/rings at stagger `slot`.
    private func fillAnimation(_ slot: Int) -> Animation? {
        entranceAnimated ? .easeOut(duration: 0.7).delay(Double(slot) * 0.06) : nil
    }

    private func entranceEffect(_ slot: Int) -> EntranceEffect {
        EntranceEffect(entered: entered, animation: entranceAnimation(slot))
    }

    /// Replays the entrance: instant reset to hidden, then the staggered
    /// reveal. Snapshot renders (revealImmediately) jump to the settled state.
    private func replayEntrance() {
        if revealImmediately {
            entranceAnimated = false
            entered = true
            return
        }
        entranceAnimated = false
        entered = false
        // Run-loop timer (not Task.sleep / main-queue async) so the flip
        // also fires in pumped run loops (snapshot harness mid-frame
        // captures) — identical behavior in-app.
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { _ in
            MainActor.assumeIsolated {
                entranceAnimated = true
                entered = true
            }
        }
    }

    /// Replays the chart draw-on: instant reset to a blank chart, then the
    /// curve sweeps in from the left (0 → 1, .easeOut 0.7). Snapshot renders
    /// jump straight to the settled state.
    private func replayChartDraw() {
        if revealImmediately {
            chartAnimated = false
            chartEntered = true
            return
        }
        chartAnimated = false
        chartEntered = false
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { _ in
            MainActor.assumeIsolated {
                chartAnimated = true
                chartEntered = true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

            ThemedDivider().padding(.horizontal, 12)

            ZStack(alignment: .top) {
                // Plain VStack — no vertical ScrollView/NSScrollView; the
                // popover auto-sizes to content via preferredContentSize.
                VStack(spacing: 7) {
                    if viewModel.notesManager.settings.aiRecommendation {
                        aiRecommendation
                    }

                    VStack(spacing: 8) {
                        HStack(alignment: .center) {
                            sectionTitle(
                                limitsPage == 2
                                    ? String(localized: "USAGE RATE", bundle: .app)
                                    : String(localized: "USAGE LIMITS", bundle: .app)
                            )
                            Spacer(minLength: 8)
                            limitsPagePicker
                        }
                        limitsPager
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassCard()

                    chartSection
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .glassCard()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .opacity(isSettingsExpanded || isInfoExpanded || isAccountExpanded ? 0 : 1)

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

                if isAccountExpanded {
                    accountPanel
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: DT.Size.popoverWidth)
        .popoverBG()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.popoverRadius))
        .preferredColorScheme(colorScheme)
        .environment(\.locale, viewModel.appLocale)
        .onAppear {
            isSettingsExpanded = false
            isInfoExpanded = false
            isAccountExpanded = false
            valuesRevealed = revealImmediately
            if revealImmediately {
                replayEntrance()
                replayChartDraw()
            } else {
                waitForDataThenReveal()
            }
            if let page = limitsPageForSnapshot {
                limitsPage = page
            }
            if collapseChartForSnapshot {
                isChartExpanded = false
            }
        }
        .onChange(of: limitsPage) { _, _ in
            // Every page switch replays the unified entrance.
            replayEntrance()
        }
        .onDisappear {
            valuesRevealed = false
            entered = false
            entranceAnimated = false
            chartEntered = false
            chartAnimated = false
        }
    }

    // MARK: - Value Reveal

    private func waitForDataThenReveal() {
        // Poll until data is loaded (run-loop timers so the reveal also
        // drains in pumped run loops — see replayEntrance).
        guard viewModel.appState.hasLoadedUsage else {
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                MainActor.assumeIsolated { waitForDataThenReveal() }
            }
            return
        }
        // Small pause so the empty state is visible briefly
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated {
                valuesRevealed = true
                // The unified entrance (fade+rise+fill) takes over from here.
                replayEntrance()
                replayChartDraw()
            }
        }
    }


    // MARK: - Header Bar (Product header)

    private var headerBar: some View {
        HStack(spacing: 0) {
            // Brand corner — logo seated in a subtle chip + app name.
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    Image("ClaudeLogo")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                }
                .frame(width: 26, height: 26)

                Text("ClaudeTakip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.80))

                refreshPill
            }

            Spacer(minLength: 8)

            // Action icons — single row, circular ghost hover states so
            // clicks feel targeted. Same buttons, same actions.
            HStack(spacing: 6) {
                HeaderIconButton(action: { viewModel.openStatusPage() }) { _ in
                    statusCloudIcon
                }

                HeaderIconButton(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isAccountExpanded.toggle()
                        isInfoExpanded = false
                        isSettingsExpanded = false
                    }
                }) { hovered in
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(isAccountExpanded ? 0.85 : hovered ? 0.70 : 0.45))
                }

                HeaderIconButton(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isInfoExpanded.toggle()
                        isSettingsExpanded = false
                        isAccountExpanded = false
                    }
                }) { hovered in
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(isInfoExpanded ? 0.85 : hovered ? 0.70 : 0.45))
                }

                HeaderIconButton(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isSettingsExpanded.toggle()
                        isInfoExpanded = false
                        isAccountExpanded = false
                    }
                }) { hovered in
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary.opacity(isSettingsExpanded ? 0.85 : hovered ? 0.70 : 0.45))
                }

                HeaderIconButton(action: { onQuit() }) { hovered in
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(hovered
                            ? AnyShapeStyle(DT.Colors.statusRed.opacity(0.90))
                            : AnyShapeStyle(.primary.opacity(0.45)))
                }
            }
        }
    }

    /// "refresh · 3 min ago" cluster as a quiet pill that reads clickable —
    /// same refresh action as before, now with a proper hit target.
    private var refreshPill: some View {
        Button(action: {
            withAnimation(DT.Animation.refreshSpin) { isRefreshing = true }
            onRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isRefreshing = false }
        }) {
            HStack(spacing: 4) {
                BI.arrowClockwise.view(size: 10)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                Text(viewModel.lastUpdateText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(viewModel.isLastUpdateWarning ? DT.Colors.statusOrange : .primary.opacity(0.65))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(isRefreshHovered ? 0.09 : 0.05)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isRefreshHovered = hovering }
        }
    }

    // MARK: - Section Title

    private func sectionTitle(_ text: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.primary.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            trailing()
        }
    }

    // MARK: - Usage Limits Pager (summary page ↔ Apple-Fitness-style rings)

    /// Top-right page switcher — labeled segmented control in the same chip
    /// language as the chart's tab picker (white active chip, 11 pt).
    private static let limitsPageCount = 3

    private var limitsPageLabels: [String] {
        [
            String(localized: "Overview", bundle: .app),
            String(localized: "All", bundle: .app),
            String(localized: "Rate", bundle: .app),
        ]
    }

    private var limitsPagePicker: some View {
        let isDark = envColorScheme == .dark
        let chipShape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let labels = limitsPageLabels

        return HStack(spacing: 3) {
            ForEach(0..<Self.limitsPageCount, id: \.self) { index in
                let isSelected = limitsPage == index
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        limitsPage = index
                    }
                }) {
                    Text(labels[index])
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(Color.primary.opacity(isSelected ? 0.85 : 0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            isSelected ? (isDark ? Color.white.opacity(0.16) : Color.white) : Color.clear,
                            in: chipShape
                        )
                        .overlay(
                            chipShape.strokeBorder(
                                isSelected && !isDark ? Color.black.opacity(0.06) : Color.clear,
                                lineWidth: 0.5
                            )
                        )
                        .shadow(
                            color: isSelected && !isDark ? .black.opacity(0.10) : .clear,
                            radius: 3,
                            y: 1
                        )
                        .contentShape(chipShape)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Manual pager — deliberately NO ScrollView/NSScrollView: on some
    /// systems the legacy horizontal scroller rendered as a black band at
    /// the card bottom. Pages are laid out in a plain offset HStack; a drag
    /// gesture snaps to the nearest page on release. An invisible ZStack of
    /// all pages sizes the pager to the tallest page's natural height.
    private var limitsPager: some View {
        ZStack {
            limitsSummaryPage.hidden()
            ringsPage.hidden()
            ratePage.hidden()
        }
        .frame(maxWidth: .infinity)
        .overlay {
            GeometryReader { geo in
                let w = geo.size.width
                let lastPage = Self.limitsPageCount - 1
                HStack(spacing: 0) {
                    limitsSummaryPage.frame(width: w)
                    ringsPage.frame(width: w)
                    ratePage.frame(width: w)
                }
                .offset(x: -CGFloat(limitsPage) * w + limitsDragOffset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            var translation = value.translation.width
                            // Rubber-band resistance past the first/last page
                            if (limitsPage == 0 && translation > 0)
                                || (limitsPage == lastPage && translation < 0) {
                                translation /= 3
                            }
                            limitsDragOffset = translation
                        }
                        .onEnded { value in
                            let threshold = w / 4
                            var target = limitsPage
                            if value.translation.width < -threshold {
                                target = min(limitsPage + 1, lastPage)
                            } else if value.translation.width > threshold {
                                target = max(limitsPage - 1, 0)
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                limitsPage = target
                                limitsDragOffset = 0
                            }
                        }
                )
            }
        }
        .clipped()
    }

    private var limitsSummaryPage: some View {
        VStack(spacing: 8) {
            timerGauges
            ThemedDivider()
            sonnetRow
            if viewModel.extraUsageVisible {
                ThemedDivider()
                extraRow
            }
        }
    }

    // Rings page — nested rings left, icon legend right.

    private struct RingSpec: Identifiable {
        let id: Int
        let color: Color
        let partner: Color
        let fraction: Double
        let label: String
        let value: String
        let sub: String
    }

    private var ringSpecs: [RingSpec] {
        var specs: [RingSpec] = [
            RingSpec(
                id: 0,
                color: DT.Colors.statusGreen,
                partner: DT.Colors.ringTipLime,
                fraction: rv(viewModel.appState.sessionUsage),
                label: String(localized: "Current Session", bundle: .app),
                value: "\(Int(rv(viewModel.appState.sessionUsage) * 100))%",
                sub: viewModel.sessionRenewalText
            ),
            RingSpec(
                id: 1,
                color: DT.Colors.claudeAccent,
                partner: DT.Colors.ringTipPink,
                fraction: rv(viewModel.appState.weeklyUsage),
                label: String(localized: "Weekly", bundle: .app),
                value: "\(Int(rv(viewModel.appState.weeklyUsage) * 100))%",
                sub: viewModel.weeklyRenewalText
            ),
            RingSpec(
                id: 2,
                color: DT.Colors.sonnetPurple,
                partner: DT.Colors.ringTipMagenta,
                fraction: rv(viewModel.sonnetBarProgress),
                label: viewModel.modelLimitName,
                value: "\(Int(rv(viewModel.sonnetBarProgress) * 100))%",
                sub: {
                    let lines = viewModel.sonnetResetLines
                    return lines.1.isEmpty ? lines.0 : "\(lines.0) \(lines.1)"
                }()
            ),
        ]
        if viewModel.extraUsageVisible {
            specs.append(RingSpec(
                id: 3,
                color: DT.Colors.extraBlue,
                partner: DT.Colors.ringTipAqua,
                fraction: rv(viewModel.extraUsageProgress),
                label: String(localized: "Extra Usage", bundle: .app),
                value: viewModel.isExtraUnlimited
                    ? viewModel.extraUsedText
                    : "\(Int(rv(viewModel.extraUsageProgress) * 100))%",
                sub: {
                    let lines = viewModel.extraResetLines
                    return lines.1.isEmpty ? lines.0 : "\(lines.0) \(lines.1)"
                }()
            ))
        }
        return specs
    }

    private var ringsPage: some View {
        let specs = ringSpecs
        return HStack(spacing: 10) {
            ZStack {
                ForEach(specs) { spec in
                    let inset = CGFloat(spec.id) * 16
                    // Apple Activity Rings mechanic (teardown-copied):
                    // base hue anchored at 12 o'clock, tip tone at the
                    // moving end; below 50% the gradient end is pinned at
                    // 6 o'clock so low arcs stay calm; track = tip @ ~10%.
                    let frac = min(1, max(0, entranceFill(spec.fraction)))
                    ZStack {
                        Circle()
                            .stroke(spec.partner.opacity(0.12), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: frac)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        spec.color,
                                        spec.color.mix(with: spec.partner, by: 0.5),
                                        spec.partner,
                                    ],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360 * max(0.5, frac))
                                ),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: spec.color.opacity(0.25), radius: 3)
                            .animation(fillAnimation(spec.id), value: entered)
                    }
                    .padding(inset)
                }
            }
            .frame(width: 146, height: 146)
            .padding(.vertical, 6)
            // Leading inset ≥ the stroke's 7 pt overflow past the ring frame,
            // so the outer ring can't bleed into the neighboring pager page.
            .padding(.leading, 8)
            .modifier(entranceEffect(0))

            // Legend — premium mini-dashboard: identity-colored values on a
            // strict grid, an inline progress hairline in each ring's hue
            // (instant row ↔ ring mapping), hairline separators between rows.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(specs) { spec in
                    if spec.id != specs.first?.id {
                        ThemedDivider()
                            .padding(.leading, 27)
                            .modifier(entranceEffect(1 + spec.id))
                    }
                    ringLegendRow(spec)
                        .modifier(entranceEffect(1 + spec.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func ringLegendRow(_ spec: RingSpec) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Plain color dot (owner pass: no SF chips) — dot hue = ring
            // hue = hairline hue for instant row ↔ ring mapping; a faint
            // same-hue halo keeps it from reading as a loose bullet.
            ZStack {
                Circle()
                    .strokeBorder(spec.color.opacity(0.22), lineWidth: 2)
                Circle()
                    .fill(spec.color)
                    .frame(width: 13, height: 13)
            }
            .frame(width: 19, height: 19)

            VStack(alignment: .leading, spacing: 3.5) {
                Text(spec.label)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Progress hairline in the ring's hue — fills with the
                // unified entrance alongside the ring itself.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(spec.color.opacity(0.22))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        spec.color,
                                        spec.color.mix(with: spec.partner, by: 0.5),
                                        spec.partner,
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(1, max(0, entranceFill(spec.fraction))))
                            .animation(fillAnimation(1 + spec.id), value: entered)
                    }
                }
                .frame(height: 5.5)

                if !spec.sub.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.55))
                        Text(spec.sub)
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.primary.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            Spacer(minLength: 6)

            Text(spec.value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(spec.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Timer Gauges (page 1 — Apple-Timer-style countdown rings)

    private var timerGauges: some View {
        HStack(spacing: 6) {
            overviewGaugeColumn(
                fraction: min(1, max(0, rv(viewModel.appState.sessionUsage))),
                color: DT.Colors.statusColor(for: viewModel.appState.sessionRemaining),
                partner: DT.Colors.auroraPartner(for: viewModel.appState.sessionRemaining),
                title: String(localized: "Current Session", bundle: .app).uppercased(),
                timeText: sessionCountdownText,
                statusText: valuesRevealed ? viewModel.sessionGaugeBadgeText : "–",
                statusColor: viewModel.sessionGaugeBadgeColor,
                resetText: viewModel.sessionRenewalText,
                slot: 0
            )
            overviewGaugeColumn(
                fraction: min(1, max(0, rv(viewModel.appState.weeklyUsage))),
                color: DT.Colors.statusColor(for: 1.0 - viewModel.appState.weeklyUsage),
                partner: DT.Colors.auroraPartner(for: 1.0 - viewModel.appState.weeklyUsage),
                title: String(localized: "Weekly", bundle: .app).uppercased(),
                timeText: viewModel.weeklyRenewalText.isEmpty ? "–" : viewModel.weeklyRenewalText,
                statusText: valuesRevealed ? viewModel.weeklyRateBadgeText : "–",
                statusColor: viewModel.weeklyRateBadgeColor,
                resetText: viewModel.weeklyRenewalText,
                slot: 1
            )
        }
    }

    /// One Overview countdown column on the shared gauge anatomy: status hue
    /// sweeping into its aurora partner for the usage fraction, remaining
    /// time in the center, the %-thumb pinned to the arc end (same fraction
    /// as the arc — never a separate calculation), and the "resets in" token
    /// below the ring.
    private func overviewGaugeColumn(
        fraction: Double,
        color: Color,
        partner: Color,
        title: String,
        timeText: String,
        statusText: String,
        statusColor: Color,
        resetText: String,
        slot: Int
    ) -> some View {
        TimerGaugeColumn(
            fraction: entranceFill(fraction),
            fill: .aurora(base: color, partner: partner),
            title: title,
            centerText: timeText,
            badgeText: statusText,
            badgeColor: statusColor,
            thumbText: "\(Int(fraction * 100))%",
            thumbColor: color,
            tokenIcon: "clock.arrow.circlepath",
            tokenLabel: String(localized: "resets in", bundle: .app),
            tokenValue: resetText,
            fillAnimation: fillAnimation(slot)
        )
        .modifier(entranceEffect(slot))
    }

    /// Compact single-line variant for the Sonnet/Extra bar rows — bold
    /// monospaced time only, so the bars get the horizontal room.
    private func inlineResetToken(_ time: String) -> some View {
        Group {
            if !time.isEmpty {
                Text(time)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.90))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        }
    }

    // MARK: - Sonnet / Extra Rows (identity bars on a clean grid)

    /// Shared row grid: [icon chip 28][name 64][bar 112][% 46][spacer][token].
    /// Percent column fits a full "100%" (a model row can be maxed out) — the
    /// bar gives back the width so the total row span is unchanged.
    private static let barRowIconSize: CGFloat = 28
    private static let barRowNameWidth: CGFloat = 64
    private static let barRowBarWidth: CGFloat = 112
    private static let barRowPercentWidth: CGFloat = 46

    private func usageBarRow(
        icon: String,
        color: Color,
        partner: Color,
        name: Text,
        sub: String?,
        progress: Double,
        resetTime: String,
        slot: Int
    ) -> some View {
        let fill = entranceFill(progress)
        return HStack(spacing: 7) {
            ZStack {
                Circle().fill(color.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: Self.barRowIconSize, height: Self.barRowIconSize)

            VStack(alignment: .leading, spacing: 1) {
                name
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.primary.opacity(0.80))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: Self.barRowNameWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color,
                                color.mix(with: partner, by: 0.55),
                                partner,
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .shadow(color: color.opacity(0.35), radius: 3)
                    .frame(width: Self.barRowBarWidth * max(0, min(1, fill)))
                    .animation(fillAnimation(slot), value: entered)
            }
            .frame(width: Self.barRowBarWidth, height: 14)

            Text("\(Int(fill * 100))%")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.barRowPercentWidth, alignment: .leading)

            Spacer(minLength: 2)

            inlineResetToken(resetTime)
                .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .modifier(entranceEffect(slot))
    }

    private var sonnetRow: some View {
        let lines = viewModel.sonnetResetLines
        return usageBarRow(
            icon: "sparkles",
            color: DT.Colors.sonnetPurple,
            partner: DT.Colors.auroraViolet,
            name: Text(viewModel.modelLimitName.uppercased()),
            sub: nil,
            progress: rv(viewModel.sonnetBarProgress),
            resetTime: lines.1.isEmpty ? lines.0 : "\(lines.0) \(lines.1)",
            slot: 2
        )
    }

    private var extraRow: some View {
        let lines = viewModel.extraResetLines
        let resetTime = lines.1.isEmpty ? lines.0 : "\(lines.0) \(lines.1)"
        return Group {
            if viewModel.isExtraUnlimited {
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(DT.Colors.extraBlue.opacity(0.14))
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DT.Colors.extraBlue)
                    }
                    .frame(width: Self.barRowIconSize, height: Self.barRowIconSize)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("EXTRA", bundle: .app)
                            .font(.system(size: 12.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.primary.opacity(0.80))
                            .minimumScaleFactor(0.85)
                        Text(viewModel.extraUsedText)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: Self.barRowNameWidth, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: "infinity")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DT.Colors.extraBlue)
                        Text("Unlimited", bundle: .app)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DT.Colors.extraBlue)
                        Text("Active", bundle: .app)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.70))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DT.Colors.extraBlue.opacity(0.10), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(DT.Colors.extraBlue.opacity(0.18), lineWidth: 0.5)
                    )

                    Spacer(minLength: 2)

                    inlineResetToken(resetTime)
                        .layoutPriority(1)
                }
                .padding(.vertical, 2)
                .modifier(entranceEffect(3))
            } else {
                usageBarRow(
                    icon: "bolt.fill",
                    color: DT.Colors.extraBlue,
                    partner: DT.Colors.auroraCyan,
                    name: Text("EXTRA", bundle: .app),
                    sub: extraSubText,
                    progress: rv(viewModel.extraUsageProgress),
                    resetTime: resetTime,
                    slot: 3
                )
            }
        }
    }

    /// "$4.20 / $25"-style balance line under the EXTRA name.
    private var extraSubText: String? {
        if let balanceText = viewModel.extraCurrentBalanceText {
            return "\(viewModel.extraUsedText) / \(balanceText)"
        }
        if let limitText = viewModel.extraMonthlyLimitText {
            return "\(viewModel.extraUsedText) \(limitText)"
        }
        return viewModel.extraUsedText
    }

    // MARK: - Usage Rate Page (third page of the USAGE LIMITS pager)

    /// Mirrors the Overview anatomy 1:1 — same shared gauge column, but the
    /// arc is a 0x–2x dial (fill = rate/2) painted with the semantic rate
    /// ramp, an ideal tick at the midpoint, the signed deviation % in the
    /// thumb, and the deviation capsule under the ring.
    private var ratePage: some View {
        HStack(spacing: 6) {
            rateGaugeColumn(
                rate: rv(viewModel.sessionRate),
                title: String(localized: "Current Session", bundle: .app).uppercased(),
                badgeText: valuesRevealed ? viewModel.sessionGaugeBadgeText : "–",
                badgeColor: viewModel.sessionGaugeBadgeColor,
                deviationText: valuesRevealed ? viewModel.sessionDeviationText : "–",
                limitReached: viewModel.appState.sessionUsage >= 1.0,
                slot: 0
            )
            rateGaugeColumn(
                rate: rv(viewModel.weeklyRate),
                title: String(localized: "Weekly", bundle: .app).uppercased(),
                badgeText: valuesRevealed ? viewModel.weeklyRateBadgeText : "–",
                badgeColor: viewModel.weeklyRateBadgeColor,
                deviationText: valuesRevealed ? viewModel.weeklyDeviationText : "–",
                limitReached: viewModel.appState.weeklyUsage >= 1.0,
                slot: 1
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func rateGaugeColumn(
        rate: Double,
        title: String,
        badgeText: String,
        badgeColor: Color,
        deviationText: String,
        limitReached: Bool,
        slot: Int
    ) -> some View {
        let clamped = min(max(rate, 0), 2.0)
        // Limit reached pegs the dial (the rate is stale once the quota is
        // gone) while the center keeps the last measured rate.
        let arcRate = limitReached ? 2.0 : clamped
        return TimerGaugeColumn(
            fraction: entranceFill(arcRate / 2.0),
            fill: .rateRamp,
            title: title,
            centerText: TimerGaugeColumn.rateText(clamped),
            centerColor: TimerGaugeColumn.rampColor(clamped),
            badgeText: badgeText,
            badgeColor: badgeColor,
            thumbText: TimerGaugeColumn.deviationPercentText(for: clamped),
            thumbColor: TimerGaugeColumn.rampColor(arcRate),
            tokenIcon: "gauge.with.needle",
            tokenLabel: String(localized: "Ideal = 1.0x", bundle: .app),
            tokenValue: deviationText,
            tokenValueIcon: TimerGaugeColumn.deviationArrow(for: clamped),
            tokenValueColor: TimerGaugeColumn.deviationColor(for: clamped),
            fillAnimation: fillAnimation(slot)
        )
        .modifier(entranceEffect(slot))
    }

    // MARK: - Timer Gauge Helpers

    /// Time remaining until the session reset — "2h 13m" style with the
    /// localized d/h/m unit tokens, matching the weekly gauge ("3d 3h").
    /// Static per render tick (the view model's 30 s clock refreshes it).
    private var sessionCountdownText: String {
        guard let reset = viewModel.appState.sessionResetDate else { return "–" }
        let remaining = max(0, Int(reset.timeIntervalSinceNow))
        let hUnit = String(localized: "h", bundle: .app)
        let mUnit = String(localized: "m", bundle: .app)
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours >= 1 {
            return "\(hours)\(hUnit) \(minutes)\(mUnit)"
        }
        return "\(max(1, minutes))\(mUnit)"
    }

    // MARK: - AI Recommendation

    private var aiRecommendation: some View {
        let strategy = viewModel.paceStrategy
        let accent = viewModel.paceStatusColor
        let unavailable = viewModel.appState.isAIUnavailable && viewModel.appState.aiPacingMessage == nil
        let isFetching = viewModel.appState.isFetchingAIMessage
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
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            } else if viewModel.appState.aiPacingMessage == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing your usage…", bundle: .app)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .strokeBorder(accent.opacity(0.15), lineWidth: 1)
                )
            } else if !strategy.isEmpty {
                Text(strategy)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isFetching ? 0.50 : 0.90))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .overlay(alignment: .topTrailing) {
                        if isFetching {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(accent.opacity(0.25))
                            .offset(x: 6, y: 6)
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.70), accent.opacity(0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: accent.opacity(0.15), radius: 6, x: 0, y: 3)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isFetching)
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Text("USAGE HISTORY", bundle: .app)
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.primary.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: isChartExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.35))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isChartExpanded {
                        isChartExpanded = false
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isChartExpanded = true
                        }
                        replayChartDraw()
                    }
                }
                Spacer()
                if isChartExpanded {
                    chartTabPicker
                } else {
                    sparklinePeek
                }
            }

            if isChartExpanded {
                switch selectedChartTab {
                case .session:
                    let sessionCapped = viewModel.appState.sessionUsage >= 1.0
                    DetailedChartView(
                        snapshots: valuesRevealed ? viewModel.appState.usageHistory : [],
                        resetDate: viewModel.appState.sessionResetDate,
                        windowDuration: TimingConstants.sessionWindowDuration,
                        color: DT.Colors.statusGreen,
                        xLabels: viewModel.sessionHourLabels,
                        predictedDepletionDate: !sessionCapped && viewModel.sessionRate > 1.0 ? viewModel.predictedDepletionDate : nil,
                        showCapMarker: sessionCapped,
                        drawProgress: chartEntered ? 1 : 0,
                        drawAnimation: chartAnimated ? .easeOut(duration: 0.7) : nil
                    )
                case .weekly:
                    let weeklyCapped = viewModel.appState.weeklyUsage >= 1.0
                    DetailedChartView(
                        snapshots: valuesRevealed ? viewModel.appState.weeklyUsageHistory : [],
                        resetDate: viewModel.appState.weeklyResetDate,
                        windowDuration: TimingConstants.weeklyWindowDuration,
                        color: DT.Colors.statusGreen,
                        xLabels: viewModel.weeklyDayLabels,
                        predictedDepletionDate: !weeklyCapped && viewModel.weeklyRate > 1.0 ? viewModel.weeklyPredictedDepletionDate : nil,
                        showCapMarker: weeklyCapped,
                        drawProgress: chartEntered ? 1 : 0,
                        drawAnimation: chartAnimated ? .easeOut(duration: 0.7) : nil
                    )
                }
            }
        }
    }

    /// Collapsed-state peek: a tiny live sparkline of the selected window so
    /// the card keeps a pulse even when folded. Tapping it expands the chart.
    private var sparklinePeek: some View {
        let isSession = selectedChartTab == .session
        return SparklinePeek(
            snapshots: valuesRevealed
                ? (isSession ? viewModel.appState.usageHistory : viewModel.appState.weeklyUsageHistory)
                : [],
            resetDate: isSession ? viewModel.appState.sessionResetDate : viewModel.appState.weeklyResetDate,
            windowDuration: isSession ? TimingConstants.sessionWindowDuration : TimingConstants.weeklyWindowDuration,
            color: DT.Colors.statusGreen,
            partner: DT.Colors.auroraTeal
        )
        .frame(width: 68, height: 18)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) {
                isChartExpanded = true
            }
            replayChartDraw()
        }
    }

    private var chartTabPicker: some View {
        let isDark = envColorScheme == .dark
        let activeColor = Color.primary.opacity(0.85)
        let inactiveColor = Color.primary.opacity(0.62)
        let activeBg = isDark ? Color.white.opacity(0.16) : Color.white
        let chipShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return HStack(spacing: 3) {
            ForEach(ChartTab.allCases, id: \.self) { tab in
                let isSelected = selectedChartTab == tab
                Button(action: {
                    guard selectedChartTab != tab else { return }
                    selectedChartTab = tab
                    // Tab switches replay the draw-on so the incoming curve
                    // never just appears.
                    replayChartDraw()
                }) {
                    Text(tab == .session ? String(localized: "Current Session", bundle: .app) : String(localized: "Weekly", bundle: .app))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? activeColor : inactiveColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? activeBg : Color.clear,
                            in: chipShape
                        )
                        .overlay(
                            chipShape.strokeBorder(
                                isSelected && !isDark ? Color.black.opacity(0.06) : Color.clear,
                                lineWidth: 0.5
                            )
                        )
                        .shadow(
                            color: isSelected && !isDark ? .black.opacity(0.10) : .clear,
                            radius: 3,
                            y: 1
                        )
                        .contentShape(chipShape)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
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
                .foregroundStyle(.primary.opacity(0.70))
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.65))
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text("v\(appVersion)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.62))
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

            HStack(spacing: 10) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.70))
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Update", bundle: .app)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text("Check for updates", bundle: .app)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.65))
                }

                Spacer(minLength: 4)

                Button(action: {
                    guard !isCheckingUpdate else { return }
                    isCheckingUpdate = true
                    onCheckUpdate?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        isCheckingUpdate = false
                    }
                }) {
                    Group {
                        if isCheckingUpdate {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Text("Check", bundle: .app)
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundStyle(DT.Colors.claudeAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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

    // MARK: - Account Panel

    private var accountPanel: some View {
        VStack(spacing: 0) {
            // Centered header
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(DT.Colors.claudeAccent.opacity(0.55))

                VStack(spacing: 4) {
                    let displayName = viewModel.appState.accountDisplayName
                        ?? viewModel.appState.accountName?.truncatedBeforeApostropheS
                    if let name = displayName {
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                    }

                    if let email = viewModel.appState.accountEmail {
                        Text(email)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.62))
                            .lineLimit(1)
                    }

                    Text(viewModel.accountPlanDisplayName)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DT.Colors.claudeAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(DT.Colors.claudeAccent.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            ThemedDivider()

            // Subscription
            if let billing = viewModel.accountBillingDisplayText {
                accountRow(
                    icon: "checkmark.seal.fill",
                    title: String(localized: "Subscription", bundle: .app),
                    desc: String(localized: "Billing status", bundle: .app),
                    value: billing,
                    valueColor: DT.Colors.statusGreen
                )
                accountDivider
            }

            // Member since
            if let memberSince = viewModel.accountMemberSinceText {
                accountRow(
                    icon: "calendar",
                    title: String(localized: "Member Since", bundle: .app),
                    desc: String(localized: "Account creation date", bundle: .app),
                    value: memberSince
                )
                accountDivider
            }

            // Extra usage
            accountRow(
                icon: "bolt.fill",
                title: String(localized: "Extra Usage", bundle: .app),
                desc: String(localized: "Overage billing", bundle: .app),
                value: viewModel.accountExtraUsageStatusText,
                valueColor: viewModel.appState.extraUsage?.isEnabled == true
                    ? DT.Colors.statusGreen : .primary.opacity(0.65)
            )

            // Spending this month
            if let spendingText = viewModel.accountSpendingText {
                accountDivider
                accountRow(
                    icon: "creditcard.fill",
                    title: String(localized: "Spent This Month", bundle: .app),
                    desc: String(localized: "Extra credits used", bundle: .app),
                    value: spendingText
                )
            }

            // Spending cap
            if let capText = viewModel.accountSpendingCapText {
                accountDivider
                accountRow(
                    icon: "shield.fill",
                    title: String(localized: "Spending Cap", bundle: .app),
                    desc: String(localized: "Monthly limit", bundle: .app),
                    value: capText
                )
            }

            accountDivider

            // Sign out
            Button(action: { onSignOut() }) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.55))
                        .frame(width: 24, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign Out", bundle: .app)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.80))
                        Text("Stop tracking usage", bundle: .app)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red.opacity(0.40))
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private var accountDivider: some View {
        ThemedDivider().padding(.leading, 44)
    }

    private func accountRow(
        icon: String,
        title: String,
        desc: String,
        value: String,
        valueColor: Color = .primary.opacity(0.80)
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.70))
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Text(desc)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.40))
            }

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var infoDivider: some View {
        ThemedDivider().padding(.leading, 44)
    }

    private func infoLinkRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.70))
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.65))
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
            if case .disconnected = viewModel.appState.connectionStatus {
                Image(systemName: "cloud.slash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.gray)
            } else {
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

// MARK: - Entrance Effect

/// Fade+rise entrance (opacity 0→1, y +8→0) driven by the shared `entered`
/// flag. `animation` is nil during resets so the hidden state applies
/// instantly; the reveal staggers via each slot's delay.
private struct EntranceEffect: ViewModifier {
    let entered: Bool
    let animation: Animation?

    func body(content: Content) -> some View {
        content
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 8)
            .animation(animation, value: entered)
    }
}

// MARK: - Header Icon Button

/// Circular ghost-hover icon button for the header bar — a quiet
/// primary-tint circle fades in under the pointer so clicks feel targeted.
private struct HeaderIconButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content(isHovered)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Sparkline Peek

/// Miniature smooth usage curve for the collapsed chart header. Reuses the
/// exact ChartMath point-mapping and Catmull-Rom clamping as the full chart.
private struct SparklinePeek: View {
    let snapshots: [UsageSnapshot]
    let resetDate: Date?
    let windowDuration: TimeInterval
    let color: Color
    let partner: Color

    var body: some View {
        Canvas { context, size in
            let points = ChartMath.points(
                snapshots: snapshots,
                resetDate: resetDate,
                windowDuration: windowDuration,
                width: size.width - 4,
                usableHeight: size.height - 4,
                topPadding: 2
            )
            guard points.count >= 2 else { return }

            var path = Path()
            path.move(to: points[0])
            if points.count == 2 {
                path.addLine(to: points[1])
            } else {
                for i in 0..<(points.count - 1) {
                    let p0 = i > 0 ? points[i - 1] : points[i]
                    let p1 = points[i]
                    let p2 = points[i + 1]
                    let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]
                    let (cp1, cp2) = ChartMath.controlPoints(p0: p0, p1: p1, p2: p2, p3: p3)
                    path.addCurve(to: p2, control1: cp1, control2: cp2)
                }
            }
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [color, partner]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            if let last = points.last {
                context.fill(
                    Circle().path(in: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)),
                    with: .color(partner)
                )
            }
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
