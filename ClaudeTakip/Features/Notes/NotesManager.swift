import Foundation
import ServiceManagement

@Observable @MainActor
final class NotesManager {
    private(set) var settings: AppSettings
    private(set) var isFirstLaunch: Bool = false
    private let userDefaultsKey = "ClaudeTakip.AppSettings"
    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        if let data = store.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaultSettings
            isFirstLaunch = true
        }
        syncLaunchAtLogin()
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        let previousLaunchAtLogin = settings.launchAtLogin
        update(&settings)
        save()
        if settings.launchAtLogin != previousLaunchAtLogin {
            syncLaunchAtLogin()
        }
    }

    private func syncLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: failed to \(settings.launchAtLogin ? "register" : "unregister"): \(error)")
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            store.set(data, forKey: userDefaultsKey)
        }
    }
}
