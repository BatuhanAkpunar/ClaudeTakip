import Foundation

/// claude.ai oturum çerezi ile konuşan istemci.
///
/// Uç noktalar ve akış MIT lisanslı `theDanButuc/Claude-Usage-Monitor`
/// projesinden alındı. Bu, Claude Code'un kullandığı `/api/oauth/usage`
/// ucundan farklı bir yol: Bearer token değil, tarayıcı oturum çerezi
/// kullanıyor ve karşılığında ekstra kullanım cüzdanını da veriyor.
public struct ClaudeWebClient: Sendable {
    public enum ClientError: Error, Sendable, Equatable {
        case notAuthenticated
        /// Oturum düşmüş, yeniden giriş gerekiyor.
        case sessionExpired
        /// Cloudflare doğrulaması. Çerez sağlam, ağ veya IP itibarı sorunlu.
        /// Bu durumda kullanıcıdan YENİDEN GİRİŞ İSTENMEZ: giriş yapmak sorunu
        /// çözmediği için kullanıcı sonsuz bir döngüye girer.
        case cloudflareChallenge
        case badResponse(Int)
        case malformed(String)
        case transport(String)
    }

    public static let host = "claude.ai"

    private let sessionKey: String
    private let session: URLSession

    /// Yalnızca bu istemciye ait, çerez SAKLAMAYAN bir oturum.
    ///
    /// `URLSession.shared` paylaşılan çerez kavanozunu kullanıyordu ve bunun
    /// iki sonucu vardı. Birincisi güvenlik: claude.ai'nin döndürdüğü her
    /// `Set-Cookie` (rotasyona uğramış oturum anahtarı dahil) Keychain'e özenle
    /// konan sırrın korumasız bir kopyasını diske yazıyordu. İkincisi
    /// kararlılık: kavanozdaki eski bir çerez, elle konan `Cookie` başlığını
    /// gölgeleyip geçerli bir anahtarla kalıcı 401 üretebiliyordu ve yeniden
    /// giriş bunu çözmüyordu, çünkü kavanoz aynı kalıyordu.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// Sunucu `Set-Cookie` ile YENİ bir `sessionKey` döndürürse çağrılır.
    ///
    /// Çerez kavanozu bilinçli olarak kapalı; ama claude.ai anahtarı zaman
    /// zaman döndürüyor ve eskisi ölüyor. Kanca olmadan yeni anahtar çöpe
    /// gidiyor, uygulama boşuna "oturum düştü" diyordu. Kavanoz yine kapalı:
    /// yalnızca bu tek çerez, yalnızca claude.ai alanından, çağırana verilir.
    public let onRotatedSessionKey: (@Sendable (String) -> Void)?

    public init(
        sessionKey: String,
        session: URLSession? = nil,
        onRotatedSessionKey: (@Sendable (String) -> Void)? = nil
    ) {
        self.sessionKey = sessionKey
        self.session = session ?? Self.makeSession()
        self.onRotatedSessionKey = onRotatedSessionKey
    }

    /// Yanıt başlıklarından döndürülmüş oturum anahtarını yakalar.
    private func captureRotatedKey(from http: HTTPURLResponse, url: URL) {
        guard let onRotatedSessionKey,
              let fields = http.allHeaderFields as? [String: String] else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard let rotated = cookies.first(where: {
            $0.name == "sessionKey" && $0.domain.hasSuffix(Self.host)
        }) else { return }
        let value = rotated.value
        guard value.hasPrefix("sk-ant-"), value.count > 20, value != sessionKey else { return }
        onRotatedSessionKey(value)
    }

    // MARK: - Uç noktalar

    /// Kullanıcının organizasyon kimliği. Kullanım ucu bunu gerektiriyor.
    public func organizationID() async throws -> String {
        let data = try await get("/api/organizations")
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ClientError.malformed("organizations listesi okunamadı")
        }
        guard let uuid = Self.selectOrganization(from: list) else {
            throw ClientError.malformed("organizasyon kimliği yok")
        }
        return uuid
    }

    /// Doğru organizasyonu seçer.
    ///
    /// Listeden ilk elemanı almak yanlış: hesapta yalnızca API erişimi olan
    /// ayrı bir organizasyon bulunabiliyor ve o listenin başına düştüğünde
    /// abonelik kotası yerine boş bir tablo geliyor. Sohbet yeteneği olan
    /// organizasyon aranıyor, bulunamazsa API-only olanlar eleniyor.
    static func selectOrganization(from list: [[String: Any]]) -> String? {
        func capabilities(_ item: [String: Any]) -> [String] {
            item["capabilities"] as? [String] ?? []
        }
        if let chat = list.first(where: { capabilities($0).contains("chat") }) {
            return chat["uuid"] as? String
        }
        if let nonAPI = list.first(where: { capabilities($0) != ["api"] }) {
            return nonAPI["uuid"] as? String
        }
        return list.first?["uuid"] as? String
    }

    /// Ham usage yanıtı. Yalnızca tanılama için: alan adları hesaba göre
    /// değiştiğinden neyin geldiğini gözle görmek gerekebiliyor.
    public func rawUsage(organizationID: String) async throws -> Data {
        try await get("/api/organizations/\(organizationID)/usage")
    }

    public func usage(organizationID: String) async throws -> ServerUsage {
        let data = try await get("/api/organizations/\(organizationID)/usage")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.malformed("usage yanıtı okunamadı")
        }
        return ServerUsage(json: root)
    }

    /// Ön ödemeli kredi bakiyesi.
    ///
    /// Ana kullanım ucu harcananı ve tavanı veriyor ama kalan bakiyeyi
    /// vermiyor; o ayrı bir uçta duruyor. Bu yüzden çağrı "en iyi çaba":
    /// hata gelirse ana veriyi bloklamadan nil dönüyor.
    public func balance(organizationID: String) async -> Balance? {
        guard let data = try? await get("/api/organizations/\(organizationID)/prepaid/credits"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Tutarlar burada da sent cinsinden.
        return Balance(
            remaining: ServerUsage.number(root["amount"]).map { $0 / 100 },
            currency: root["currency"] as? String ?? "USD",
            autoReloadEnabled: root["auto_reload_settings"] != nil
                && !(root["auto_reload_settings"] is NSNull)
        )
    }

    public struct Balance: Sendable, Equatable {
        public let remaining: Double?
        public let currency: String
        public let autoReloadEnabled: Bool
    }

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
    public static func headers(sessionKey: String) -> [String: String] {
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

    /// Taklit edilen tarayıcı sürümü. Çok eskimesi Cloudflare'in şüphesini
    /// artırdığı için altı ayda bir güncellenmeli.
    /// Chrome'un ana sürümü. UA ile client-hint başlıkları AYNI sürümü
    /// söylemeli: Cloudflare ikisinin uyumsuzluğunu puanlıyor. Sürüm
    /// chromiumdash "Stable/Mac" kanalından alındı (2026-09: 152).
    /// Altı ayda bir güncelle.
    static let chromeMajor = "152"

    public static let chromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/\(chromeMajor).0.0.0 Safari/537.36"

    /// Giriş penceresinin kullandığı Safari kimliği. Google, gömülü webview
    /// tespit ettiğinde OAuth'u reddediyor.
    public static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    // MARK: - Oturum penceresi başlatma

    /// 5 saatlik kullanım penceresini başlatır ve arkasında iz bırakmaz.
    ///
    /// Pencere claude.ai tarafında İLK MESAJLA açılıyor; yalnızca konuşma
    /// yaratmak yetmiyor, gerçek bir `completion` şart. Bu yüzden akış üç adım:
    /// konuşma aç → en ucuz modele tek kelimelik istem gönder → konuşmayı sil.
    /// Silme, kullanıcının sohbet geçmişini kirletmemek için.
    ///
    /// UYARI: Bu, uygulamanın kullanıcı adına içerik ürettiği TEK yer. Geri
    /// kalan her şey salt okuma. Anthropic Tüketici Şartları §3.7 hizmete
    /// "otomatik ya da insan olmayan yollarla" erişimi API anahtarı dışında
    /// yasakladığı için çağıran taraf bunu kullanıcı onayı olmadan, kendi
    /// başına zamanlamamalı.
    ///
    /// - Returns: Pencerenin gerçekten açıldığı doğrulanmadı; yalnızca
    ///   isteklerin hatasız geçtiği. Doğrulama bir sonraki `usage` okumasında.
    public func startSessionWindow(organizationID: String) async throws {
        let conversationID = UUID().uuidString.lowercased()
        let base = "/api/organizations/\(organizationID)/chat_conversations"

        _ = try await send(
            base, method: "POST",
            body: ["uuid": conversationID, "name": ""]
        )

        // Tek kelimelik istem, en ucuz model: amaç cevap değil, pencerenin
        // açılması. Yanıt akış (SSE) olarak dönüyor, gövdesi okunmuyor.
        _ = try? await send(
            "\(base)/\(conversationID)/completion", method: "POST",
            body: [
                "prompt": "hi",
                "timezone": TimeZone.current.identifier,
                "model": Self.cheapestModel,
            ],
            timeout: 30
        )

        // Temizlik en iyi çaba: silme başarısız olsa bile pencere açıldı.
        _ = try? await send("\(base)/\(conversationID)", method: "DELETE", body: nil)
    }

    /// Pencereyi açmak için kullanılan model. En ucuz/en hızlı olan seçiliyor:
    /// amaç bir cevap almak değil, sayacı başlatmak.
    static let cheapestModel = "claude-haiku-4-5-20251001"

    // MARK: - Taşıma

    /// Gövdeli istek (POST/DELETE). `get` ile aynı başlık ve çerez kuralları.
    @discardableResult
    private func send(
        _ path: String, method: String, body: [String: String]?, timeout: TimeInterval = 15
    ) async throws -> Data {
        guard var components = URLComponents(string: "https://\(Self.host)") else {
            throw ClientError.transport("adres kurulamadı")
        }
        components.path = path
        guard let url = components.url else {
            throw ClientError.transport("adres kurulamadı")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        for (name, value) in Self.headers(sessionKey: sessionKey) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(-1)
        }
        captureRotatedKey(from: http, url: url)
        switch http.statusCode {
        case 200...299: return data
        case 401: throw ClientError.sessionExpired
        case 403: throw Self.classifyForbidden(response: http, body: data)
        default: throw ClientError.badResponse(http.statusCode)
        }
    }

    private func get(_ path: String) async throws -> Data {
        guard var components = URLComponents(string: "https://\(Self.host)") else {
            throw ClientError.transport("adres kurulamadı")
        }
        components.path = path
        guard let url = components.url else {
            throw ClientError.transport("adres kurulamadı")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Kimlik YALNIZCA elle konan başlıktan gelsin: kavanoz devrede olsaydı
        // iki kaynak çakışır ve hangisinin gittiği belirsizleşirdi.
        request.httpShouldHandleCookies = false
        for (name, value) in Self.headers(sessionKey: sessionKey) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(-1)
        }
        captureRotatedKey(from: http, url: url)
        switch http.statusCode {
        case 200: return data
        // Cloudflare 401 ile doğrulama yapmıyor, bu koşulsuz oturum sorunudur.
        case 401: throw ClientError.sessionExpired
        case 403: throw Self.classifyForbidden(response: http, body: data)
        default: throw ClientError.badResponse(http.statusCode)
        }
    }

    /// 403'ün sebebini ayırt eder.
    ///
    /// claude.ai'nin kendisi Cloudflare arkasında sunuluyor, yani `cf-ray` ve
    /// `server: cloudflare` başlıkları meşru uygulama yanıtlarında da var.
    /// Yalnızca onlara bakmak teşhisi tersine çevirir. Bunun yerine önce kesin
    /// doğrulama kanıtı aranıyor, sonra uygulama katmanı pozitif doğrulanıyor.
    static func classifyForbidden(response: HTTPURLResponse, body: Data) -> ClientError {
        if response.value(forHTTPHeaderField: "cf-mitigated") != nil {
            return .cloudflareChallenge
        }
        let contentType = (response.value(forHTTPHeaderField: "content-type") ?? "").lowercased()
        if contentType.contains("text/html") {
            // Uygulama katmanı JSON döner, HTML gelmesi doğrulama sayfası demektir.
            return .cloudflareChallenge
        }
        if contentType.contains("application/json"),
           (try? JSONSerialization.jsonObject(with: body)) != nil {
            return .sessionExpired
        }
        // Emin olunamıyorsa oturum sorunu VARSAYILMAZ: yanlış varsayım
        // kullanıcıyı çözmeyecek bir girişe zorluyor.
        return .cloudflareChallenge
    }
}

/// Sunucudan gelen kullanım tablosu.
///
/// Alan adları zamanla değişiyor (model bazlı kotalar bir dönem üst seviyedeydi,
/// sonra diziye taşındı), bu yüzden ayrıştırma savunmacı: tanınmayan alanlar
/// sessizce atlanıyor, eksik alanlar nil kalıyor.
public struct ServerUsage: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        public let utilization: Double
        public let resetsAt: Date?
    }

    public struct Wallet: Sendable, Equatable {
        public let isEnabled: Bool
        /// Aylık harcama tavanı, ana para birimi cinsinden (sent değil).
        /// Sıfır veya nil ise tavan yok demektir.
        public let monthlyLimit: Double?
        /// Bu dönemde harcanan kredi, ana para birimi cinsinden.
        public let usedCredits: Double?
        /// Tavanın kullanılan yüzdesi. 100'ü aşabilir.
        public let utilization: Double?
        public let currency: String
        /// Harcama tavanına ulaşıldı mı. Ulaşıldıysa ekstra kullanım genelde
        /// otomatik duraklatılıyor; bu "kullanıcı kapattı"dan çok farklı bir durum.
        public let spendLimitReached: Bool
        /// Sunucunun verdiği kapatma sebebi kodu (`org_level_disabled_until` vb.).
        public let disabledReasonCode: String?

    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    /// Model bazlı haftalık kotalar, gösterim adıyla eşlenmiş.
    public let modelWindows: [String: Window]
    public let wallet: Wallet?

    init(json: [String: Any]) {
        fiveHour = Self.window(json["five_hour"])
        sevenDay = Self.window(json["seven_day"])

        var models: [String: Window] = [:]
        // Eski şema: üst seviyede model başına alan.
        //
        // `seven_day_omelette` bilinçli olarak DIŞARIDA: o ayrı bir kota değil,
        // ana `seven_day` havuzunun kendisi. Listeye eklendiğinde aynı sayı
        // kartta iki kez görünüyor.
        for (key, label) in [
            "seven_day_opus": "Opus",
            "seven_day_sonnet": "Sonnet",
        ] where json[key] != nil {
            if let window = Self.window(json[key]) { models[label] = window }
        }
        // Yeni şema: `limits` dizisi, her elemanda kapsam adı.
        if let limits = json["limits"] as? [[String: Any]] {
            for entry in limits {
                // Yalnızca MODEL kapsamlı kayıtlar: `session` ve `weekly_all`
                // zaten `five_hour`/`seven_day` olarak okunuyor, onları model
                // listesine de koymak aynı sayıyı iki kez gösterirdi.
                let scope = entry["scope"] as? [String: Any]
                guard let model = scope?["model"] as? [String: Any],
                      let name = model["display_name"] as? String,
                      let window = Self.window(entry)
                else { continue }
                models[name] = window
            }
        }
        modelWindows = models

        if let extra = json["extra_usage"] as? [String: Any] {
            // Para alanları SENT cinsinden geliyor: 2050 = 20,50 USD.
            // Doğrudan göstermek tutarı yüz katına çıkarır.
            let limit = Self.number(extra["monthly_limit"]).map { $0 / 100 }
            let spent = Self.number(extra["used_credits"]).map { $0 / 100 }
            // Sunucu `is_enabled` alanını her zaman göndermiyor. Yokluğunda
            // "kapalı" varsaymak, tutarları gösterirken "Kapalı" yazan bir kart
            // üretiyordu. Tavan ya da harcama varsa cüzdan zaten açıktır.
            let hasAmounts = (limit ?? 0) > 0 || (spent ?? 0) > 0
            wallet = Wallet(
                isEnabled: extra["is_enabled"] as? Bool ?? hasAmounts,
                // Sıfır tavan "limitsiz" demek, gösterilecek bir sayı değil.
                monthlyLimit: (limit ?? 0) > 0 ? limit : nil,
                usedCredits: spent,
                utilization: Self.number(extra["utilization"]),
                currency: extra["currency"] as? String ?? "USD",
                spendLimitReached: Self.number(extra["spend_limit_reached"]) == 1
                    || (extra["spend_limit_reached"] as? Bool ?? false),
                disabledReasonCode: extra["disabled_reason"] as? String
            )
        } else {
            wallet = nil
        }
    }

    private static func window(_ raw: Any?) -> Window? {
        guard let object = raw as? [String: Any] else { return nil }
        // Yüzde alanının adı şemaya göre değişiyor: üst seviye pencerelerde
        // `utilization`, eski sürümlerde `used_percentage`, `limits` dizisinin
        // elemanlarında ise `percent`. `percent` eksikti ve bu yüzden model
        // bazlı kotalar (Fable dahil) hiç ayrıştırılamıyordu: dizi okunuyor
        // ama her eleman bu kontrolde eleniyordu, `modelWindows` hep boş
        // kalıyor ve arayüz gerçek kota yerine yerel tahmine düşüyordu.
        guard let value = number(object["utilization"])
            ?? number(object["used_percentage"])
            ?? number(object["percent"])
        else {
            return nil
        }
        return Window(utilization: value, resetsAt: date(object["resets_at"]))
    }

    static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
