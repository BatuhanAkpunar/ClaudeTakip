import Foundation

extension ClaudeWebClient {
    // MARK: - Başlıklar

    /// Cloudflare'in bot korumasını geçmek için gereken tam tarayıcı başlık seti.
    ///
    /// Yalnızca `Cookie` göndermek yetmiyor: Cloudflare `sec-fetch-*` alanlarına,
    /// `origin`/`referer` tutarlılığına ve `user-agent` ile diğer başlıkların
    /// birbirini doğrulamasına bakıyor. Eksik başlıkla istek challenge sayfasına
    /// düşüyor ve JSON yerine HTML dönüyor.
    ///
    /// Başlık listesi MIT lisanslı `f-is-h/Usage4Claude` projesindeki
    /// `ClaudeAPIHeaderBuilder` dosyasından alındı.
    static func headers(sessionKey: String) -> [String: String] {
        [
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "content-type": "application/json",

            // Anthropic'in kendi web istemcisi bu iki başlığı gönderiyor.
            "anthropic-client-platform": "web_claude_ai",
            "anthropic-client-version": "1.0.0",

            "user-agent": chromeUserAgent,
            // Client hints: gerçek Chrome bunları UA ile birlikte gönderiyor.
            // UA var, bunlar yokken istek "taklit" profiline daha yakın düşüyordu.
            "sec-ch-ua": "\"Chromium\";v=\"\(chromeMajor)\", \"Google Chrome\";v=\"\(chromeMajor)\", \"Not-A.Brand\";v=\"99\"",
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": "\"macOS\"",
            "origin": "https://\(host)",
            // Gerçek tarayıcıda bu istek kullanım ayarları sayfasından çıkıyor.
            "referer": "https://\(host)/settings/usage",

            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",

            "Cookie": "sessionKey=\(sessionKey)",
        ]
    }

    /// Taklit edilen Chrome'un ana sürümü. UA ile client-hint başlıkları AYNI
    /// sürümü söylemeli: Cloudflare ikisinin uyumsuzluğunu puanlıyor. Sürüm
    /// chromiumdash "Stable/Mac" kanalından alındı (2026-09: 152). Çok eskimesi
    /// Cloudflare'in şüphesini artırdığı için altı ayda bir güncellenmeli.
    static let chromeMajor = "152"

    static let chromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/\(chromeMajor).0.0.0 Safari/537.36"

    /// Giriş penceresinin kullandığı Safari kimliği. Google, gömülü webview
    /// tespit ettiğinde OAuth'u reddediyor.
    public static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.6 Safari/605.1.15"
}
