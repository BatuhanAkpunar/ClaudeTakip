import UserNotifications

@MainActor
final class NotificationManager {
    private let appState: AppState
    private let notesManager: NotesManager
    private let soundPlayer = SoundPlayer()
    private var triggerState = PacingTriggerState()

    init(appState: AppState, notesManager: NotesManager) {
        self.appState = appState
        self.notesManager = notesManager
        requestPermission()
    }

    func evaluateTriggers() {
        let settings = notesManager.settings

        // Hizli tuketim uyarisi
        if settings.fastConsumptionAlert,
           appState.paceStatus == .fast || appState.paceStatus == .critical,
           triggerState.fastAlertCount < PacingConstants.maxFastAlertPerSession {
            triggerState.fastAlertCount += 1
            sendNotification(
                title: "Hizli tuketiyorsun",
                body: "Bu hizda limitin erken bitebilir. Biraz yavaslamak iyi olabilir."
            )
            if settings.soundEnabled { soundPlayer.playNotificationSound() }
        }

        // Kritik esik uyarisi
        if settings.criticalThresholdAlert,
           appState.sessionRemaining < PacingConstants.criticalRemainingThreshold,
           !triggerState.criticalAlertFired {
            triggerState.criticalAlertFired = true
            sendNotification(
                title: "Limit bitmek uzere",
                body: "Mesaj hakkinin %\(Int(appState.sessionRemaining * 100))'i kaldi."
            )
            if settings.soundEnabled { soundPlayer.playNotificationSound() }
        }

        // Sifirlama tespiti
        if settings.resetNotification,
           let prev = appState.previousUsage,
           prev > 0.1, appState.sessionUsage < 0.01,
           !triggerState.resetAlertFired {
            triggerState.resetAlertFired = true
            sendNotification(
                title: "Hakkin yenilendi!",
                body: "5 saatlik penceren sifirlandi. Keyifli kullanmalar."
            )
            if settings.soundEnabled { soundPlayer.playNotificationSound() }
            // Reset sonrasi trigger state temizle
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.triggerState.resetForNewSession()
            }
        }
    }

    // MARK: - Private

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
