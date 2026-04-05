import Foundation
import Testing
@testable import ClaudeTakip

@Suite @MainActor struct NotesManagerTests {

    private func makeManager() -> NotesManager {
        let suiteName = "NotesManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return NotesManager(store: defaults)
    }

    @Test func defaultSettings() {
        let manager = makeManager()
        #expect(manager.settings.launchAtLogin == false)
        #expect(manager.settings.autoSession == false)
        #expect(manager.settings.autoUpdate == true)
        #expect(manager.settings.darkMode == nil)
    }

    @Test func updateSettings() {
        let manager = makeManager()
        manager.updateSettings { $0.darkMode = true }
        #expect(manager.settings.darkMode == true)
        manager.updateSettings { $0.launchAtLogin = true }
        #expect(manager.settings.launchAtLogin == true)
    }
}
