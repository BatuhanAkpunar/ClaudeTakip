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
    private lazy var usageService = UsageService(appState: appState, authManager: authManager)
    private lazy var statusService = StatusService(appState: appState)
    private lazy var notificationManager = NotificationManager(appState: appState, notesManager: notesManager)
    private lazy var autoSessionService = AutoSessionService(appState: appState, authManager: authManager, notesManager: notesManager)
    private lazy var iconRenderer = MenuBarIconRenderer()
    private var viewModel: MenuBarViewModel?

    // Timers & tasks
    private var iconUpdateTimer: Timer?
    private var pacingTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupGlobalMonitor()
        setupWakeObserver()

        Task {
            await authManager.checkExistingSession()
            if appState.isLoggedIn {
                startServices()
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
        let image = iconRenderer.render(remaining: appState.sessionRemaining, resetTimeText: resetText)
        statusItem?.button?.image = image

        // Flash animation for <10%
        if appState.sessionRemaining < 0.10 && appState.isLoggedIn {
            iconRenderer.startFlashAnimation { [weak self] in
                Task { @MainActor [weak self] in
                    self?.updateIcon()
                }
            }
        } else {
            iconRenderer.stopFlashAnimation()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        if appState.isLoggedIn {
            viewModel?.stopClockTick()
            let vm = MenuBarViewModel(
                appState: appState,
                notesManager: notesManager,
                statusService: statusService
            )
            self.viewModel = vm
            let view = MenuBarView(
                viewModel: vm,
                onRefresh: { [weak self] in
                    Task { await self?.usageService.manualRefresh() }
                },
                onSignOut: { [weak self] in self?.handleSignOut() },
                onQuit: { NSApp.terminate(nil) },
                onHeightChange: { [weak self] height in
                    guard let self, let vm = self.viewModel else { return }
                    let width = vm.isNotesOpen
                        ? DT.Size.popoverWidth + DT.Size.notesPanelWidth + 1
                        : DT.Size.popoverWidth
                    self.popover?.contentSize = NSSize(width: width, height: height)
                }
            )
            let hostingController = NSHostingController(rootView: view)
            hostingController.sizingOptions = []
            popover?.contentViewController = hostingController
            popover?.contentSize = NSSize(width: DT.Size.popoverWidth, height: 520)
        } else {
            let loginView = LoginView { [weak self] sessionKey in
                Task { [weak self] in
                    try? await self?.authManager.handleLoginCookie(sessionKey)
                    self?.updatePopoverContent()
                    self?.startServices()
                }
            }
            let hostingController = NSHostingController(rootView: loginView)
            hostingController.sizingOptions = []
            popover?.contentViewController = hostingController
            popover?.contentSize = NSSize(width: DT.Size.popoverWidth, height: 400)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Services

    private func startServices() {
        usageService.startPolling()
        statusService.startPolling()
        autoSessionService.startMonitoring()
        viewModel?.startClockTick()
        startPacingObservation()
    }

    private func startPacingObservation() {
        pacingTask?.cancel()
        pacingTask = Task { @MainActor [weak self] in
            var previousUsage = self?.appState.sessionUsage ?? 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let currentUsage = appState.sessionUsage
                if currentUsage != previousUsage {
                    let remainingMinutes: Double
                    if let resetDate = appState.sessionResetDate {
                        remainingMinutes = max(0, resetDate.timeIntervalSince(Date()) / 60)
                    } else {
                        remainingMinutes = TimingConstants.sessionWindowDuration / 60
                    }
                    appState.paceStatus = PacingEngine.calculatePaceStatus(
                        currentUsage: currentUsage,
                        previousUsage: appState.previousUsage,
                        remainingMinutes: remainingMinutes,
                        pollIntervalMinutes: TimingConstants.usagePollingInterval / 60
                    )
                    notificationManager.evaluateTriggers()
                    previousUsage = currentUsage
                }
            }
        }
    }

    private func handleSignOut() {
        let alert = NSAlert()
        alert.messageText = "Hesaptan cikmak istediginize emin misiniz?"
        alert.informativeText = "Oturum verileri silinecek."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hesaptan Cik")
        alert.addButton(withTitle: "Vazgec")
        alert.buttons.first?.hasDestructiveAction = true

        if alert.runModal() == .alertFirstButtonReturn {
            pacingTask?.cancel()
            pacingTask = nil
            viewModel?.stopClockTick()
            usageService.stopPolling()
            statusService.stopPolling()
            autoSessionService.stopMonitoring()
            authManager.signOut()
            updatePopoverContent()
        }
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
        iconRenderer.stopFlashAnimation()
        pacingTask?.cancel()
        pacingTask = nil
        viewModel?.stopClockTick()
        usageService.stopPolling()
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
