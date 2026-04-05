import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        LanguageManager.apply(notesManager.settings.language)
        setupStatusItem()
        setupPopover()
        setupGlobalMonitor()
        setupWakeObserver()

        Task {
            await authManager.checkExistingSession()
            if appState.isLoggedIn {
                updatePopoverContent()
                startServices()
            } else {
                // If not logged in, open the popover automatically
                if let button = statusItem?.button {
                    popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
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
            hasLoaded: appState.hasLoadedUsage
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
            let view = MenuBarView(
                viewModel: vm,
                onRefresh: refreshAction,
                onSignOut: signOutAction,
                onQuit: quitAction
            )
            let hostingController = NSHostingController(rootView: view)
            hostingController.sizingOptions = [.preferredContentSize]
            popover?.contentViewController = hostingController
        } else {
            let loginView = LoginView { [weak self] sessionKey in
                Task { [weak self] in
                    try? await self?.authManager.handleLoginCookie(sessionKey)
                    self?.updatePopoverContent()
                    self?.startServices()
                }
            }
            let hostingController = NSHostingController(rootView: loginView)
            hostingController.sizingOptions = [.intrinsicContentSize]
            popover?.contentViewController = hostingController
            popover?.contentSize = NSSize(width: popoverWidth, height: 480)
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

    // MARK: - Services

    private func startServices() {
        usageService.onSessionExpired = { [weak self] in
            self?.handleSessionExpired()
        }

        // Independent services start immediately
        statusService.startPolling()
        autoSessionService.startMonitoring()

        // Load cache histories + start polling timer
        usageService.startPolling()

        // Coordinated startup: API -> Pacing -> Groq -> UI
        Task { [weak self] in
            guard let self else { return }

            // 1. Fetch fresh data
            await usageService.fetchUsage()

            // 2. Calculate pacing immediately
            performImmediatePacing()

            // 3. Get Groq message (wait max 8s)
            await pacingMessageService.fetchInitialMessage(timeout: 8)

            // 4. Ready — show UI
            appState.hasLoadedUsage = true
            viewModel?.startClockTick()
            startPacingObservation()
        }

        // Safety net: show anyway if not loaded within 15s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !appState.hasLoadedUsage else { return }
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
            pollIntervalMinutes: TimingConstants.usagePollingInterval / 60
        )
    }

    private func handleSessionExpired() {
        pacingTask?.cancel()
        pacingTask = nil
        viewModel?.stopClockTick()
        usageService.stopPolling()
        statusService.stopPolling()
        autoSessionService.stopMonitoring()
        pacingMessageService.reset()
        cacheStore.clearAll()
        authManager.signOut()
        updatePopoverContent()
        updateIcon()
    }

    private func startPacingObservation() {
        pacingTask?.cancel()
        pacingTask = Task { @MainActor [weak self] in
            var lastResetFetchTriggered = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                guard appState.hasLoadedUsage else { continue }

                // Fetch new data immediately when reset time passes
                if let resetDate = appState.sessionResetDate, resetDate < Date() {
                    if !lastResetFetchTriggered {
                        lastResetFetchTriggered = true
                        await usageService.fetchUsage()
                        continue
                    }
                } else {
                    lastResetFetchTriggered = false
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
                    remainingMinutes: remainingMinutes,
                    pollIntervalMinutes: TimingConstants.usagePollingInterval / 60
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
        alert.informativeText = String(localized: "Session data will be deleted.", bundle: .app)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Sign Out", bundle: .app))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .app))
        alert.buttons.first?.hasDestructiveAction = true

        if alert.runModal() == .alertFirstButtonReturn {
            pacingTask?.cancel()
            pacingTask = nil
            viewModel?.stopClockTick()
            usageService.stopPolling()
            statusService.stopPolling()
            autoSessionService.stopMonitoring()
            pacingMessageService.reset()
            cacheStore.clearAll()
            authManager.signOut()
            updatePopoverContent()
            updateIcon()
        }
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
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = nil
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
