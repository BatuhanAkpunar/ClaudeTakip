import Testing
import Foundation
@testable import LimitCore

@Suite("Sunucu istemcisi")
struct ClaudeWebClientTests {
    @Test("Organizasyon seçimi API-only org'u atlar")
    func picksChatOrganization() {
        let list: [[String: Any]] = [
            ["uuid": "api-org", "capabilities": ["api"]],
            ["uuid": "chat-org", "capabilities": ["chat", "claude_pro"]],
        ]
        // İlk elemanı almak API-only org'u seçerdi ve kota tablosu boş gelirdi.
        #expect(ClaudeWebClient.selectOrganization(from: list) == "chat-org")
    }

    @Test("Yetenek bilgisi yoksa ilk organizasyona düşülür")
    func fallsBackToFirst() {
        let list: [[String: Any]] = [["uuid": "only-org"]]
        #expect(ClaudeWebClient.selectOrganization(from: list) == "only-org")
    }

    @Test("Cüzdan tutarları sentten çevrilir")
    func walletConvertsCents() throws {
        let json: [String: Any] = [
            "extra_usage": [
                "is_enabled": true,
                "monthly_limit": 2050,
                "used_credits": 347,
                "utilization": 16.9,
            ],
        ]
        let wallet = try #require(ServerUsage(json: json).wallet)
        #expect(wallet.monthlyLimit == 20.50)
        #expect(wallet.usedCredits == 3.47)
        #expect(wallet.utilization == 16.9)
    }

    @Test("Sıfır aylık tavan limitsiz demek, sayı olarak gösterilmez")
    func zeroLimitMeansUnlimited() throws {
        let json: [String: Any] = [
            "extra_usage": ["is_enabled": true, "monthly_limit": 0, "used_credits": 100],
        ]
        let wallet = try #require(ServerUsage(json: json).wallet)
        #expect(wallet.monthlyLimit == nil)
        #expect(wallet.usedCredits == 1.0)
    }

    @Test("seven_day_omelette ayrı bir kota olarak sayılmaz")
    func omeletteIsNotASeparateQuota() {
        let json: [String: Any] = [
            "seven_day": ["utilization": 15.0],
            "seven_day_omelette": ["utilization": 15.0],
            "seven_day_sonnet": ["utilization": 1.0],
        ]
        let usage = ServerUsage(json: json)
        // Aynı havuz iki kez listelenirse kartta çift görünüyordu.
        #expect(usage.modelWindows["Fable"] == nil)
        #expect(usage.modelWindows["Sonnet"] != nil)
        #expect(usage.sevenDay?.utilization == 15.0)
    }

    // MARK: - Çerez alan adı

    /// `domain.contains("claude.ai")` denetimi "claude.ai.saldirgan.com"
    /// alan adını da kabul ediyordu.
    @Test("Alan adı sonek olarak eşleşmeli")
    func cookieDomainSuffix() {
        #expect(ClaudeWebClient.isClaudeCookieDomain("claude.ai"))
        #expect(ClaudeWebClient.isClaudeCookieDomain(".claude.ai"))
        #expect(ClaudeWebClient.isClaudeCookieDomain("api.claude.ai"))
        #expect(!ClaudeWebClient.isClaudeCookieDomain("claude.ai.saldirgan.com"))
        #expect(!ClaudeWebClient.isClaudeCookieDomain("sahteclaude.ai"))
        #expect(!ClaudeWebClient.isClaudeCookieDomain("claude.aim"))
    }

    /// Döndürülen anahtar yakalanırken de aynı alan adı kuralı geçerli:
    /// `hasSuffix("claude.ai")` "sahteclaude.ai"yi kabul ediyordu.
    @Test("Döndürülen oturum çerezi yalnızca claude.ai alanından kabul edilir")
    func rotatedCookieDomain() throws {
        func cookie(_ name: String, _ domain: String) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [
                .name: name, .value: "sk-ant-" + String(repeating: "y", count: 24),
                .domain: domain, .path: "/",
            ]))
        }
        #expect(ClaudeWebClient.isSessionCookie(try cookie("sessionKey", ".claude.ai")))
        #expect(ClaudeWebClient.isSessionCookie(try cookie("sessionKey", "claude.ai")))
        #expect(!ClaudeWebClient.isSessionCookie(try cookie("sessionKey", "sahteclaude.ai")))
        #expect(!ClaudeWebClient.isSessionCookie(try cookie("sessionKey", ".sahteclaude.ai")))
        #expect(!ClaudeWebClient.isSessionCookie(try cookie("other", ".claude.ai")))
    }

    /// 20 karakter sınırı ve `sk-ant-` öneki; ikisi de gerekli.
    @Test("Oturum anahtarı biçimi")
    func plausibleSessionKey() {
        #expect(!ClaudeWebClient.isPlausibleSessionKey("sk-ant-" + String(repeating: "x", count: 13)))
        #expect(ClaudeWebClient.isPlausibleSessionKey("sk-ant-" + String(repeating: "x", count: 14)))
        #expect(!ClaudeWebClient.isPlausibleSessionKey("sk-xxx-" + String(repeating: "x", count: 20)))
    }
}

/// İstemcinin ağa çıkmadan sınanabilen kuralları: 403 teşhisi ve tarayıcı
/// başlıkları.
///
/// 403'ün yanlış sınıflandırılması kullanıcıyı çözmeyecek bir girişe ya da
/// sonsuz bir Cloudflare döngüsüne sokar. Başlık seti ise Cloudflare'in bot
/// korumasını geçip geçmemeyi belirliyor. İkisi de bugünkü hâliyle kilitleniyor.
@Suite("İstemci kuralları")
struct ClaudeWebClientRulesTests {

    // MARK: - 403 teşhisi

    @Test("cf-mitigated başlığı doğrulama sayılır")
    func forbiddenWithMitigationHeader() {
        #expect(Self.classify(["cf-mitigated": "challenge"]) == .cloudflareChallenge)
        // Başlık, geçerli bir JSON gövdesinden önce geliyor.
        #expect(Self.classify(
            ["cf-mitigated": "challenge", "content-type": "application/json"], body: "{}"
        ) == .cloudflareChallenge)
    }

    @Test("HTML gövde doğrulama sayılır")
    func forbiddenWithHTML() {
        #expect(Self.classify(["content-type": "text/html; charset=UTF-8"],
                              body: "<html></html>") == .cloudflareChallenge)
    }

    @Test("Ayrıştırılabilen JSON oturum sorunu sayılır")
    func forbiddenWithJSON() {
        #expect(Self.classify(["content-type": "application/json"], body: "{}") == .sessionExpired)
    }

    @Test("Ayrıştırılamayan JSON doğrulama sayılır")
    func forbiddenWithBrokenJSON() {
        #expect(Self.classify(["content-type": "application/json"], body: "garbage")
            == .cloudflareChallenge)
    }

    @Test("İçerik tipi yoksa oturum sorunu varsayılmaz")
    func forbiddenWithoutContentType() {
        #expect(Self.classify([:], body: "{}") == .cloudflareChallenge)
    }

    @Test("İptal edilen istek taşıma hatası sayılmaz")
    func cancellationIsNotTransport() {
        #expect(ClaudeWebClient.transportError(URLError(.cancelled)) is CancellationError)
        #expect(ClaudeWebClient.transportError(CancellationError()) is CancellationError)
        let offline = ClaudeWebClient.transportError(URLError(.notConnectedToInternet))
        #expect(!(offline is CancellationError))
        #expect(offline as? ClaudeWebClient.ClientError != nil)
    }

    // MARK: - Başlıklar

    @Test("UA ile client-hint aynı Chrome sürümünü söyler")
    func headersAgreeOnChromeVersion() throws {
        let headers = ClaudeWebClient.headers(sessionKey: "k")
        let userAgent = try #require(headers["user-agent"])
        let clientHints = try #require(headers["sec-ch-ua"])
        #expect(userAgent.contains("Chrome/\(ClaudeWebClient.chromeMajor)"))
        #expect(clientHints.contains("v=\"\(ClaudeWebClient.chromeMajor)\""))
        #expect(headers["Cookie"] == "sessionKey=k")
    }

    private static func classify(_ fields: [String: String], body: String = "") -> ClaudeWebClient.ClientError {
        let response = HTTPURLResponse(
            url: URL(string: "https://\(ClaudeWebClient.host)/api/organizations")!,
            statusCode: 403,
            httpVersion: "HTTP/1.1",
            headerFields: fields
        )!
        return ClaudeWebClient.classifyForbidden(response: response, body: Data(body.utf8))
    }
}
