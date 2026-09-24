import Testing
import Foundation
@testable import LimitCore

/// `/usage` yanıtını ayrıştıran kuralların karakterizasyonu.
///
/// Girdiler gerçek yolla aynı biçimde kuruluyor: metin `JSONSerialization`
/// ile okunup `ServerUsage(json:)`'a veriliyor. Sayılar ve mantıksal değerler
/// böylece sunucudan gelirken olduğu gibi `NSNumber` olarak ulaşıyor. Buradaki
/// beklentiler bugünkü kodun ürettiği sonuç; kod değiştiğinde kırılmaları
/// amaçlanıyor.
@Suite("Sunucu kullanımı ayrıştırma")
struct ServerUsageTests {

    @Test("limits dizisinden yalnızca model kapsamlı kayıt alınır")
    func limitsArray() throws {
        let usage = try Self.parse("""
            {"limits":[
              {"kind":"session","group":"five_hour","percent":17,
               "resets_at":"2026-09-18T10:00:00.000Z","scope":{"model":null,"surface":null}},
              {"kind":"weekly_all","group":"seven_day","percent":42,
               "resets_at":"2026-09-18T10:00:00.000Z","scope":{"model":null,"surface":null}},
              {"kind":"weekly_scoped","group":"seven_day_fable","percent":4,
               "resets_at":"2026-09-18T10:00:00.000Z",
               "scope":{"model":{"id":"claude-fable","display_name":"Fable"},"surface":null}}
            ]}
            """)
        #expect(Array(usage.modelWindows.keys) == ["Fable"])
        #expect(usage.modelWindows["Fable"]?.utilization == 4)
        // `session` ve `weekly_all` üst seviye pencereleri de doldurmuyor:
        // onlar yalnızca `five_hour`/`seven_day` alanlarından okunuyor.
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay == nil)
    }

    @Test("utilization yoksa used_percentage okunur")
    func usedPercentageFallback() throws {
        let usage = try Self.parse("""
            {"five_hour":{"used_percentage":33.5},
             "seven_day":{"utilization":10,"used_percentage":90}}
            """)
        let fiveHour = try #require(usage.fiveHour)
        #expect(fiveHour.utilization == 33.5)
        #expect(fiveHour.resetsAt == nil)
        // İkisi birden varsa `utilization` önce geliyor.
        #expect(usage.sevenDay?.utilization == 10)
    }

    @Test("resets_at kesirli ve kesirsiz biçimde aynı anı verir")
    func resetsAtBothForms() throws {
        let usage = try Self.parse("""
            {"five_hour":{"utilization":1,"resets_at":"2026-09-18T10:00:00.000Z"},
             "seven_day":{"utilization":1,"resets_at":"2026-09-18T10:00:00Z"}}
            """)
        let withFraction = try #require(usage.fiveHour?.resetsAt)
        let plain = try #require(usage.sevenDay?.resetsAt)
        #expect(withFraction == plain)
        #expect(abs(plain.timeIntervalSince1970 - 1_789_725_600) < 0.0005)
    }

    @Test("spend_limit_reached hem 1 hem true olarak sayılır")
    func spendLimitReached() throws {
        let asNumber = try Self.wallet("""
            {"extra_usage":{"spend_limit_reached":1}}
            """)
        #expect(asNumber.spendLimitReached)

        let asBool = try Self.wallet("""
            {"extra_usage":{"spend_limit_reached":true}}
            """)
        #expect(asBool.spendLimitReached)

        let absent = try Self.wallet("""
            {"extra_usage":{}}
            """)
        #expect(absent.spendLimitReached == false)
    }

    @Test("is_enabled yoksa tutarlardan çıkarılır")
    func isEnabledInferred() throws {
        let spent = try Self.wallet("""
            {"extra_usage":{"used_credits":347}}
            """)
        #expect(spent.isEnabled)

        let empty = try Self.wallet("""
            {"extra_usage":{}}
            """)
        #expect(empty.isEnabled == false)

        // Açık `false` tutarlara rağmen korunur.
        let explicit = try Self.wallet("""
            {"extra_usage":{"is_enabled":false,"used_credits":347}}
            """)
        #expect(explicit.isEnabled == false)
    }

    @Test("Para birimi verilmezse USD")
    func currencyDefault() throws {
        let missing = try Self.wallet("""
            {"extra_usage":{"is_enabled":true}}
            """)
        #expect(missing.currency == "USD")

        let given = try Self.wallet("""
            {"extra_usage":{"is_enabled":true,"currency":"EUR"}}
            """)
        #expect(given.currency == "EUR")
    }

    @Test("Pencere kapalılığı: resets_at yoksa ya da geçmişteyse kapalı")
    func windowClosed() {
        let now = Date(timeIntervalSince1970: 1_787_344_332)
        #expect(ServerUsage.Window(utilization: 10, resetsAt: nil).isClosed(at: now))
        #expect(ServerUsage.Window(utilization: 10, resetsAt: now.addingTimeInterval(-1)).isClosed(at: now))
        #expect(ServerUsage.Window(utilization: 10, resetsAt: now).isClosed(at: now))
        #expect(ServerUsage.Window(utilization: 10, resetsAt: now.addingTimeInterval(60)).isClosed(at: now) == false)
    }

    @Test("Model kotası büyük/küçük harf duyarsız bulunur")
    func modelWindowMatching() throws {
        let usage = try Self.parse("""
            {"limits":[{"kind":"weekly_scoped","percent":4,
               "resets_at":"2026-09-18T10:00:00.000Z",
               "scope":{"model":{"id":"claude-fable","display_name":"Fable"},"surface":null}}]}
            """)
        #expect(usage.modelWindow(matching: "fable")?.utilization == 4)
        #expect(usage.modelWindow(matching: "FABLE")?.utilization == 4)
        #expect(usage.modelWindow(matching: "opus") == nil)
    }

    @Test("Sunucu okumasından arşiv örneği yuvarlanır; pencere eksikse nil")
    func sampleFromServer() throws {
        let date = Date(timeIntervalSince1970: 1_787_344_332)
        let full = try Self.parse("""
            {"five_hour":{"utilization":47.6,"resets_at":"2026-09-18T10:00:00.000Z"},
             "seven_day":{"utilization":12.4,"resets_at":"2026-09-20T10:00:00.000Z"},
             "extra_usage":{"is_enabled":true,"utilization":99.5}}
            """)
        let sample = try #require(QuotaSample(server: full, date: date, org: "org-1"))
        #expect(sample == QuotaSample(date: date, org: "org-1", fiveHour: 48, sevenDay: 12, extraUsage: 100))

        let missing = try Self.parse("""
            {"five_hour":{"utilization":47.6,"resets_at":"2026-09-18T10:00:00.000Z"}}
            """)
        #expect(QuotaSample(server: missing, date: date, org: "org-1") == nil)
    }

    @Test("ISO-8601 kesirli/kesirsiz okunur; milisaniye dönüşümü gidiş-dönüş korunur")
    func dateCodecs() throws {
        let fractional = try #require(ISO8601Parsing.date(from: "2026-09-18T10:00:00.000Z"))
        let plain = try #require(ISO8601Parsing.date(from: "2026-09-18T10:00:00Z"))
        #expect(fractional == plain)
        #expect(ISO8601Parsing.date(from: "garbage") == nil)
        #expect(Date(epochMilliseconds: 1787344332573).epochMilliseconds == 1787344332573)
    }

    @Test("Bakiye sentten dolara çevrilir; otomatik yükleme yalnızca nesneyle açık")
    func balanceParsing() throws {
        func balance(_ text: String) throws -> ClaudeWebClient.Balance {
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
            let root = try #require(object as? [String: Any])
            return try #require(ClaudeWebClient.Balance(json: root))
        }
        #expect(try balance(#"{"amount":3380}"#).remaining == 33.8)
        #expect(try balance(#"{"amount":3380,"auto_reload_settings":null}"#).autoReloadEnabled == false)
        #expect(try balance(#"{"amount":3380}"#).autoReloadEnabled == false)
        #expect(try balance(#"{"amount":3380,"auto_reload_settings":{"enabled":true}}"#).autoReloadEnabled == true)
    }

    /// `ClaudeWebClient.usage` ile aynı yol: metin → sözlük → `ServerUsage`.
    private static func parse(_ text: String) throws -> ServerUsage {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let root = try #require(object as? [String: Any])
        return ServerUsage(json: root)
    }

    /// `extra_usage` nesnesi varken cüzdan her zaman kuruluyor.
    private static func wallet(_ text: String) throws -> ServerUsage.Wallet {
        let usage = try parse(text)
        return try #require(usage.wallet)
    }
}
