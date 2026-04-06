import AppKit
import SwiftUI
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var loginWindow: NSWindow?
    private var globalMonitor: Any?
    private var wakeObserver: Any?

    // Managers
    private let appState = AppState()
    private lazy var notesManager = NotesManager()
    private lazy var authManager = AuthManager(appState: appState)
    private lazy var cacheStore = UsageCacheStore()
    private lazy var usageService = UsageService(appState: appState, authManager: authManager, cacheStore: cacheStore)
    private lazy var statusService = StatusService(appState: appState)
    private lazy var autoSessionService = AutoSessionService(appState: appState, authManager: authManager, notesManager: notesManager)
    private lazy var iconRenderer = MenuBarIconRenderer()
    private lazy var pacingMessageService = PacingMessageService(appState: appState, notesManager: notesManager)
    private lazy var updateManager = UpdateManager()
    private var viewModel: MenuBarViewModel?

    // Timers & tasks
    private var iconUpdateTimer: Timer?
    private var pacingTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var safetyNetTask: Task<Void, Never>?
    private var isHandlingSessionExpired = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeychainService().migrateFromKeychainIfNeeded()
        if notesManager.isFirstLaunch {
            applySystemDefaults()
        }
        LanguageManager.apply(notesManager.settings.language)
        setupStatusItem()
        setupPopover()
        setupGlobalMonitor()
        setupWakeObserver()

        Task {
            await authManager.checkExistingSession()
            if appState.isLoggedIn {
                if let orgId = appState.organizationId {
                    cacheStore.configure(orgId: orgId)
                }
                updatePopoverContent()
                startServices()
            } else {
                // Not logged in — popover will show WelcomeView when user clicks the icon
            }
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self
        updateIcon()

        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateIcon()
            }
        }
    }

    private func updateIcon() {
        let resetText = MenuBarIconRenderer.formatResetTime(from: appState.sessionResetDate)
        let image = iconRenderer.render(
            remaining: appState.sessionRemaining,
            resetTimeText: resetText,
            hasLoaded: appState.isLoggedIn && appState.hasLoadedUsage
        )
        statusItem?.button?.image = image
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        let popoverWidth = DT.Size.popoverWidth
        if appState.isLoggedIn {
            viewModel?.stopClockTick()
            let vm = MenuBarViewModel(
                appState: appState,
                notesManager: notesManager,
                statusService: statusService
            )
            self.viewModel = vm
            let refreshAction: () -> Void = { [weak self] in
                Task { await self?.usageService.manualRefresh() }
            }
            let signOutAction: () -> Void = { [weak self] in self?.handleSignOut() }
            let quitAction: () -> Void = { NSApp.terminate(nil) }
            let startSessionAction: () -> Void = { [weak self] in
                Task {
                    await self?.autoSessionService.startSessionNow()
                    await self?.usageService.fetchUsage()
                }
            }
            let checkUpdateAction: () -> Void = { [weak self] in self?.checkForUpdates() }
            let view = MenuBarView(
                viewModel: vm,
                onRefresh: refreshAction,
                onSignOut: signOutAction,
                onQuit: quitAction,
                onStartSession: startSessionAction,
                onCheckUpdate: checkUpdateAction
            )
            let hostingController = NSHostingController(rootView: view)
            hostingController.sizingOptions = [.preferredContentSize]
            popover?.contentViewController = hostingController
        } else {
            let welcomeView = WelcomeView { [weak self] in
                self?.popover?.performClose(nil)
                self?.openLoginWindow()
            }
            let hostingController = NSHostingController(rootView: welcomeView)
            hostingController.sizingOptions = [.intrinsicContentSize]
            popover?.contentViewController = hostingController
            popover?.contentSize = NSSize(width: popoverWidth, height: 300)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            pacingMessageService.onPopoverOpen()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Login Window

    private func openLoginWindow() {
        // Close existing window if any
        loginWindow?.close()

        let loginWebView = LoginWebView { [weak self] sessionKey in
            Task { @MainActor [weak self] in
                self?.loginWindow?.close()
                self?.loginWindow = nil
                try? await self?.authManager.handleLoginCookie(sessionKey)
                if let orgId = self?.appState.organizationId {
                    self?.cacheStore.configure(orgId: orgId)
                }
                self?.updatePopoverContent()
                self?.startServices()
                // Reopen popover to show dashboard
                if let button = self?.statusItem?.button {
                    self?.popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        }

        let hostingController = NSHostingController(rootView: loginWebView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ClaudeTakip — Sign In"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 680))
        window.minSize = NSSize(width: 400, height: 500)
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        loginWindow = window
    }

    // MARK: - Services

    private func startServices() {
        usageService.onSessionExpired = { [weak self] in
            self?.handleSessionExpired()
        }
        autoSessionService.onSessionStarted = { [weak self] in
            await self?.usageService.fetchUsage()
            self?.autoSessionService.scheduleIfNeeded()
        }

        // Independent services start immediately
        statusService.startPolling()

        // Load cache histories + start polling timer
        usageService.startPolling()

        // Coordinated startup: API -> Pacing -> Groq -> UI
        startupTask = Task { [weak self] in
            guard let self else { return }

            // 0. Fetch account details (plan, billing, etc.)
            await usageService.fetchAccountDetails()

            // 1. Fetch fresh data
            await usageService.fetchUsage()
            guard !Task.isCancelled else { return }

            // 2. Schedule auto-session based on fresh reset date
            autoSessionService.scheduleIfNeeded()

            // 3. Calculate pacing immediately
            performImmediatePacing()

            // 3. Get Groq message (wait max 8s)
            await pacingMessageService.fetchInitialMessage(timeout: 8)
            guard !Task.isCancelled else { return }

            // 4. Ready — show UI
            appState.hasLoadedUsage = true
            viewModel?.startClockTick()
            startPacingObservation()

            // 5. Auto-start session if no active session exists
            await autoSessionService.checkOnLaunch()
        }

        // Safety net: show anyway if not loaded within 15s
        safetyNetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, !appState.hasLoadedUsage else { return }
            appState.hasLoadedUsage = true
            viewModel?.startClockTick()
            startPacingObservation()
        }
    }

    private func performImmediatePacing() {
        let currentUsage = appState.sessionUsage
        let remainingMinutes: Double
        if let resetDate = appState.sessionResetDate {
            remainingMinutes = max(0, resetDate.timeIntervalSince(Date()) / 60)
        } else {
            remainingMinutes = TimingConstants.sessionWindowDuration / 60
        }

        appState.paceStatus = PacingEngine.calculatePaceStatus(
            currentUsage: currentUsage,
            previousUsage: appState.previousUsage,
            totalWindowMinutes: TimingConstants.sessionWindowDuration / 60,
            remainingMinutes: remainingMinutes,
            weeklyUsage: appState.weeklyUsage
        )
    }

    private func handleSessionExpired() {
        guard !isHandlingSessionExpired else { return }
        isHandlingSessionExpired = true
        defer { isHandlingSessionExpired = false }

        startupTask?.cancel()
        startupTask = nil
        safetyNetTask?.cancel()
        safetyNetTask = nil
        pacingTask?.cancel()
        pacingTask = nil
        viewModel?.stopClockTick()
        usageService.stopPolling()
        statusService.stopPolling()
        autoSessionService.stopMonitoring()
        autoSessionService.resetState()
        pacingMessageService.reset()
        cacheStore.forceFlush()
        cacheStore.clearInMemory()
        clearPerUserDefaults()
        authManager.signOut()
        updatePopoverContent()
        updateIcon()
    }

    private func startPacingObservation() {
        pacingTask?.cancel()
        pacingTask = Task { @MainActor [weak self] in
            var lastResetFetchDate: Date?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                guard appState.hasLoadedUsage else { continue }

                // Fetch new data immediately when reset time passes
                if let resetDate = appState.sessionResetDate, resetDate < Date() {
                    let alreadyFetched = lastResetFetchDate.map { abs($0.timeIntervalSince(resetDate)) < 1 } ?? false
                    if !alreadyFetched {
                        lastResetFetchDate = resetDate
                        await usageService.fetchUsage()
                        autoSessionService.scheduleIfNeeded()
                        continue
                    }
                } else {
                    lastResetFetchDate = nil
                    autoSessionService.scheduleIfNeeded()
                }

                let currentUsage = appState.sessionUsage
                let remainingMinutes: Double
                if let resetDate = appState.sessionResetDate {
                    remainingMinutes = max(0, resetDate.timeIntervalSince(Date()) / 60)
                } else {
                    remainingMinutes = TimingConstants.sessionWindowDuration / 60
                }

                let previousState = appState.paceStatus
                let newState = PacingEngine.calculatePaceStatus(
                    currentUsage: currentUsage,
                    previousUsage: appState.previousUsage,
                    totalWindowMinutes: TimingConstants.sessionWindowDuration / 60,
                    remainingMinutes: remainingMinutes
                )
                appState.paceStatus = newState

                // When state changes, clear old AI message, show static fallback
                if newState != previousState {
                    appState.aiPacingMessage = nil
                    pacingMessageService.onStateChanged(to: newState)
                }

                // Stale cache check — same status for more than 1 hour
                pacingMessageService.onStaleCacheCheck()
            }
        }
    }

    private func handleSignOut() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Are you sure you want to sign out?", bundle: .app)
        alert.informativeText = String(localized: "ClaudeTakip will stop tracking your usage until you sign in again.", bundle: .app)
        alert.alertStyle = .warning
        if let logo = NSImage(named: "ClaudeLogo") {
            logo.size = NSSize(width: 80, height: 80)
            alert.icon = logo
        }
        alert.addButton(withTitle: String(localized: "Sign Out", bundle: .app))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .app))
        alert.buttons.first?.hasDestructiveAction = true

        // Make the alert wider for a more spacious look
        let window = alert.window
        let frame = window.frame
        let newWidth: CGFloat = 380
        let widthDiff = newWidth - frame.width
        window.setFrame(NSRect(
            x: frame.origin.x - widthDiff / 2,
            y: frame.origin.y,
            width: newWidth,
            height: frame.height
        ), display: false)

        if alert.runModal() == .alertFirstButtonReturn {
            startupTask?.cancel()
            startupTask = nil
            safetyNetTask?.cancel()
            safetyNetTask = nil
            pacingTask?.cancel()
            pacingTask = nil
            viewModel?.stopClockTick()
            usageService.stopPolling()
            statusService.stopPolling()
            autoSessionService.stopMonitoring()
            autoSessionService.resetState()
            pacingMessageService.reset()
            cacheStore.forceFlush()
            cacheStore.clearInMemory()
            clearPerUserDefaults()
            authManager.signOut()
            updatePopoverContent()
            updateIcon()
        }
    }

    // MARK: - First Launch Defaults

    private func applySystemDefaults() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let lang = detectSystemLanguage()
        notesManager.updateSettings {
            $0.darkMode = isDark
            $0.language = lang
        }
    }

    private func detectSystemLanguage() -> String {
        let supported = ["en", "tr", "es", "fr", "de", "it", "nl", "ja", "ko", "zh-Hans", "zh-Hant", "ru", "ar", "pt-BR"]
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("zh-Hant") { return "zh-Hant" }
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            if preferred.hasPrefix("pt") { return "pt-BR" }
            if supported.contains(preferred) { return preferred }
            let base = String(preferred.prefix(while: { $0 != "-" }))
            if supported.contains(base) { return base }
        }
        return "en"
    }

    /// Removes UserDefaults keys that store per-user data.
    private func clearPerUserDefaults() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastSessionOverflowDate)
    }

    func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    // MARK: - Global Monitor

    private func setupGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
        }
    }

    // MARK: - Wake from Sleep

    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.usageService.fetchUsage()
            }
        }
    }

    // MARK: - Cleanup

    func applicationWillTerminate(_ notification: Notification) {
        loginWindow?.close()
        loginWindow = nil
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = nil
        startupTask?.cancel()
        safetyNetTask?.cancel()
        pacingTask?.cancel()
        pacingTask = nil
        viewModel?.stopClockTick()
        cacheStore.forceFlush()
        usageService.shutdown()
        statusService.stopPolling()
        autoSessionService.stopMonitoring()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
}
