import Foundation

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
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            store.set(data, forKey: userDefaultsKey)
        }
    }
}
