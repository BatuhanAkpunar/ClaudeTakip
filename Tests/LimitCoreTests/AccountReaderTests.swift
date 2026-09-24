import Testing
import Foundation
@testable import LimitCore

/// `~/.claude.json` okuyucusunun karakterizasyonu.
///
/// Plan adı arayüzde doğrudan görünüyor ve Max 5x ile Max 20x ayrımını
/// yalnızca hız limiti kademesi taşıyor. Tablo bugünkü eşlemenin birebir
/// kopyası; yeni bir plan eklendiğinde ya da bir dal değiştiğinde kırılır.
@Suite("Hesap okuma")
struct AccountReaderTests {

    @Test("Plan adı kademeden, sonra organizasyon tipinden okunur")
    func planLabelTable() {
        let table: [(tier: String?, orgType: String?, label: String?)] = [
            // Kademe tanınırsa organizasyon tipine bakılmaz.
            ("default_claude_max_5x", nil, "Max 5x"),
            ("default_claude_max_20x", nil, "Max 20x"),
            ("default_claude_pro", nil, "Pro"),
            ("default_claude_pro", "claude_max", "Pro"),
            ("default_claude_max_20x", "claude_team", "Max 20x"),
            // Kademe tanınmazsa organizasyon tipine düşülür.
            (nil, "claude_max", "Max"),
            (nil, "claude_pro", "Pro"),
            (nil, "claude_team", "Team"),
            (nil, "claude_enterprise", "Enterprise"),
            ("default_raven", "claude_team", "Team"),
            // İkisi de tanınmazsa.
            // İkisi de tanınmazsa nil: gösterim metni arayüzde yerelleşiyor,
            // buluta dile bağlı bir dize gitmiyor.
            (nil, nil, nil),
            ("default_raven", "claude_free", nil),
        ]
        for row in table {
            #expect(AccountReader.planLabel(rateLimitTier: row.tier, organizationType: row.orgType)
                == row.label, "\(row.tier ?? "nil") / \(row.orgType ?? "nil")")
        }
    }

    @Test("Hesap dosyası bugünkü alan adlarıyla okunur")
    func readFixture() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
            {
              "numStartups": 12,
              "cachedExtraUsageDisabledReason": "org_level_disabled",
              "oauthAccount": {
                "displayName": "Deneme",
                "emailAddress": "deneme@example.com",
                "organizationRateLimitTier": "default_claude_max_5x",
                "organizationType": "claude_max",
                "subscriptionCreatedAt": "2025-03-14T09:26:53.123Z",
                "hasExtraUsageEnabled": true,
                "profileFetchedAt": 1787344332573
              }
            }
            """.utf8).write(to: url)

        let account = try #require(AccountReader(url: url).read())
        #expect(account.displayName == "Deneme")
        #expect(account.email == "deneme@example.com")
        #expect(account.planLabel == "Max 5x")
        let start = try #require(account.subscriptionStart)
        #expect(abs(start.timeIntervalSince1970 - 1_741_944_413.123) < 0.0005)
        #expect(account.hasExtraUsage)
        // Sebep kodu `oauthAccount` içinde değil, kökte.
        #expect(account.extraUsageDisabledReason == "org_level_disabled")
        // `profileFetchedAt` milisaniye.
        let fetched = try #require(account.profileFetchedAt)
        #expect(abs(fetched.timeIntervalSince1970 - 1_787_344_332.573) < 0.0005)
    }

    @Test("oauthAccount yoksa ya da dosya yoksa hesap yok")
    func readMissing() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"numStartups": 12}"#.utf8).write(to: url)
        #expect(AccountReader(url: url).read() == nil)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("hesap-yok-\(UUID().uuidString).json")
        #expect(AccountReader(url: missing).read() == nil)
    }

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hesap-\(UUID().uuidString).json")
    }
}
