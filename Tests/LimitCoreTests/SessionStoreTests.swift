import Testing
import Foundation
@testable import LimitCore

@Suite("Oturum saklama")
struct SessionStoreTests {
    private func makeStore() -> (SessionStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ct-session-\(UUID().uuidString).json")
        // Keychain'e dokunmamak için teste özel servis adı.
        let keychain = KeychainStore(service: "ClaudeTakipTest-\(UUID().uuidString)", account: "t")
        return (SessionStore(url: url, keychain: keychain), url)
    }

    @Test("Oturum yazılıp geri okunuyor")
    func roundTrip() throws {
        let (store, url) = makeStore()
        defer { store.clear(); try? FileManager.default.removeItem(at: url) }

        let session = SessionStore.Session(sessionKey: "sk-ant-sid02-abc", organizationID: "org-9")
        // Bu iddia bir hatadan doğdu: `.completeFileProtection` macOS'ta yazmayı
        // engelliyordu ve kaydetme sessizce başarısız oluyordu.
        #expect(store.save(session))

        let read = try #require(store.load())
        #expect(read.sessionKey == session.sessionKey)
        #expect(read.organizationID == "org-9")
    }

    @Test("Temizlenince oturum kalmıyor")
    func clearRemoves() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.save(SessionStore.Session(sessionKey: "sk-x", organizationID: nil))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("Dosya yoksa nil döner, çökmez")
    func missingFile() {
        let store = SessionStore(
            url: URL(fileURLWithPath: "/nonexistent/dir/session.json"),
            keychain: KeychainStore(service: "ClaudeTakipTest-missing", account: "t")
        )
        #expect(store.load() == nil)
    }

    @Test("Kaydedilen dosya yalnızca sahibine açık")
    func fileIsPrivate() throws {
        let (store, url) = makeStore()
        defer { store.clear(); try? FileManager.default.removeItem(at: url) }

        store.save(SessionStore.Session(sessionKey: "sk-secret", organizationID: nil))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(permissions == 0o600)
    }

    @Test("Süre uyarısı: 3 gün eşiği ve yukarı yuvarlama")
    func expiryWarning() {
        let now = Date(timeIntervalSince1970: 1_787_344_332)
        func warning(_ left: TimeInterval) -> SessionStore.SessionExpiryWarning? {
            SessionStore.expiryWarning(expiresAt: now.addingTimeInterval(left), now: now)
        }
        #expect(warning(4 * 86400) == nil)
        #expect(warning(72 * 3600) == nil)
        #expect(warning(71 * 3600) == .expiresWithin(days: 3))
        #expect(warning(1) == .expiresWithin(days: 1))
        #expect(warning(0) == .expired)
        #expect(warning(-3600) == .expired)
    }

    @Test("Kuruluş kimliği eklenirken son kullanma ve kayıt anı korunuyor")
    func withOrganizationKeepsExpiry() {
        let saved = Date(timeIntervalSince1970: 1_787_000_000)
        let expires = Date(timeIntervalSince1970: 1_790_000_000)
        let session = SessionStore.Session(sessionKey: "sk-ant-sid02-abc", organizationID: nil,
                                           savedAt: saved, expiresAt: expires)
        let updated = session.with(organizationID: "org-9")
        #expect(updated.organizationID == "org-9")
        #expect(updated.sessionKey == session.sessionKey)
        #expect(updated.savedAt == saved)
        #expect(updated.expiresAt == expires)
    }
}
