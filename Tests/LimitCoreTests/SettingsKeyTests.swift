import Testing
import Foundation
@testable import LimitCore

@Suite("Ayar anahtarları")
struct SettingsKeyTests {
    @Test("Anahtar dizeleri ve varsayılan sabit")
    func rawStrings() {
        #expect(SettingsKey.autoSessionEnabled == "autoSessionEnabled")
        #expect(SettingsKey.autoSessionDefault == true)
        #expect(SettingsKey.cloudSyncEnabled == "cloudSyncEnabled")
        #expect(SettingsKey.purgedLegacyKeychain == "purgedLegacyKeychain")
        #expect(SettingsKey.showInMenuBar == "showInMenuBar")
    }

    @Test("Eski Keychain temizliği bayrağı bir kez koyar ve korur")
    func purgeOnce() throws {
        let suite = "test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ct-purge-\(UUID().uuidString).json")
        let store = SessionStore(url: url, keychain: KeychainStore(service: "ClaudeLimitTest", account: "purge"))

        #expect(defaults.bool(forKey: SettingsKey.purgedLegacyKeychain) == false)
        store.purgeLegacyKeychainItemOnce(defaults: defaults)
        #expect(defaults.bool(forKey: SettingsKey.purgedLegacyKeychain) == true)
        store.purgeLegacyKeychainItemOnce(defaults: defaults)
        #expect(defaults.bool(forKey: SettingsKey.purgedLegacyKeychain) == true)
    }
}
