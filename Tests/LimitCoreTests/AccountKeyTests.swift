import Testing
import Foundation
@testable import LimitCore

/// Hesap bazlı kalıcılık.
///
/// Bulut verisinin kanonik sahibi cihaz değil hesap; anahtar türetiminin
/// kararlı ve geri döndürülemez olması bunun ön şartı.
@Suite("Hesap anahtarı")
struct AccountKeyTests {
    @Test("Aynı hesap her cihazda aynı anahtarı üretir")
    func deterministic() {
        let org = "00000000-0000-4000-8000-000000000001"
        // Cihaz değiştirmenin simülasyonu: aynı girdi, ayrı çağrılar.
        #expect(AccountKey.derive(organizationID: org) == AccountKey.derive(organizationID: org))
        #expect(AccountKey.isValid(AccountKey.derive(organizationID: org)))
    }

    @Test("Farklı hesaplar çakışmaz")
    func distinct() {
        let a = AccountKey.derive(organizationID: "org-a")
        let b = AccountKey.derive(organizationID: "org-b")
        #expect(a != b)
    }

    @Test("Ham organizasyon kimliği anahtarda görünmez")
    func opaque() {
        let org = "00000000-0000-4000-8000-000000000001"
        let key = AccountKey.derive(organizationID: org)
        // Özet, girdiyi ne içerir ne de ondan türetilebilir bir parça taşır.
        #expect(!key.contains("00000000-0000-4000"))
        #expect(key.count == 64)
    }

    @Test("Boşluk ve boş girdi güvenli")
    func whitespace() {
        let org = "  org-x  "
        #expect(AccountKey.derive(organizationID: org) == AccountKey.derive(organizationID: "org-x"))
        #expect(AccountKey.derive(organizationID: "").isEmpty)
        #expect(!AccountKey.isValid(""))
        #expect(!AccountKey.isValid("ABC"))
    }
}
