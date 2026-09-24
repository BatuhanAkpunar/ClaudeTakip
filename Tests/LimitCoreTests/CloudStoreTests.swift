import Testing
import Foundation
@testable import LimitCore

@Suite("Bulut deposu")
struct CloudStoreTests {
    @Test("Bulut deposu hesap anahtarını saklar ve bırakır")
    func store() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CloudStore(url: url)

        store.save(identity: CloudIdentity(deviceID: "d1", secret: "s1"))
        store.save(uploadedThrough: Date(timeIntervalSince1970: 1000))
        #expect(store.accountKey == nil)

        let key = AccountKey.derive(organizationID: "org-a")
        store.save(accountKey: key)
        #expect(store.accountKey == key)
        // Kimlik ve işaret korunmalı: hesabı benimsemek cihazı sıfırlamaz.
        #expect(store.identity?.deviceID == "d1")

        // İşaret sıfırlama: hiç yüklenmemiş satırlar hesaba gitsin.
        store.resetWatermark()
        #expect(store.uploadedThrough == nil)
        #expect(store.accountKey == key)

        // Çıkış: anahtar bırakılır, cihaz kimliği durur.
        store.save(accountKey: nil)
        #expect(store.accountKey == nil)
        #expect(store.identity?.deviceID == "d1")
    }

    @Test("Kimliği atmak hesap anahtarını korur")
    func clearIdentityKeepsAccount() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CloudStore(url: url)
        let key = AccountKey.derive(organizationID: "org-a")
        store.save(identity: CloudIdentity(deviceID: "d1", secret: "s1"))
        store.save(uploadedThrough: Date(timeIntervalSince1970: 1000))
        store.save(accountKey: key)

        store.clearIdentity()
        #expect(store.identity == nil)
        #expect(store.uploadedThrough == nil)
        #expect(store.accountKey == key)
    }

    @Test("Bulut dosyası yalnızca kullanıcıya okunur (0600)")
    func filePermissions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        CloudStore(url: url).save(identity: CloudIdentity(deviceID: "d1", secret: "s1"))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(permissions == 0o600)
    }
}
