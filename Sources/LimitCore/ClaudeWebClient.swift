import Foundation

/// claude.ai oturum çerezi ile konuşan istemci.
///
/// Uç noktalar ve akış MIT lisanslı `theDanButuc/Claude-Usage-Monitor`
/// projesinden alındı. Bu, Claude Code'un kullandığı `/api/oauth/usage`
/// ucundan farklı bir yol: Bearer token değil, tarayıcı oturum çerezi
/// kullanıyor ve karşılığında ekstra kullanım cüzdanını da veriyor.
public struct ClaudeWebClient: Sendable {
    public enum ClientError: Error, Sendable, Equatable {
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

    /// Giriş sayfası; giriş penceresi hem ilk açılışta hem "Yeniden dene"de bunu yükler.
    public static let loginURL = URL(string: "https://\(host)/login")!

    /// Çerez gerçekten claude.ai'ye mi ait.
    ///
    /// Çerez alan adları başında noktayla gelebiliyor (".claude.ai"), bu yüzden
    /// hem tam eşleşme hem de nokta önekli sonek kabul ediliyor.
    public static func isClaudeCookieDomain(_ domain: String) -> Bool {
        let host = ClaudeWebClient.host
        return domain == host || domain == "." + host || domain.hasSuffix("." + host)
    }

    /// Değer gerçek bir oturum anahtarı gibi görünüyor mu. Çıkış yapıldığında
    /// çerez boş bir değerle yeniden yazılabiliyor; gerçek anahtar her zaman
    /// `sk-ant-` ile başlıyor.
    public static func isPlausibleSessionKey(_ value: String) -> Bool {
        value.count > 20 && value.hasPrefix("sk-ant-")
    }

    private let sessionKey: String
    private let session: URLSession

    /// Yalnızca bu istemciye ait, çerez SAKLAMAYAN bir oturum.
    ///
    /// `URLSession.shared` KULLANMA; paylaşılan çerez kavanozunun iki sorunu
    /// var. Güvenlik: claude.ai'nin döndürdüğü her `Set-Cookie` (rotasyona
    /// uğramış oturum anahtarı dahil) sırrın korumasız bir kopyasını diske
    /// yazar. Kararlılık: kavanozdaki eski bir çerez, elle konan `Cookie`
    /// başlığını gölgeleyip geçerli bir anahtarla kalıcı 401 üretebilir ve
    /// yeniden giriş bunu çözmez, çünkü kavanoz aynı kalır.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// Tüm istemcilerin paylaştığı TEK oturum.
    ///
    /// Her `ClaudeWebClient` (yani her yenileme) için yeni bir oturum açılıp
    /// hiç `invalidate` edilmiyordu; her biri kendi bağlantı havuzunu ve
    /// temsilci kuyruğunu süreç boyunca tutuyordu. Paylaşmak güvenli: çerez
    /// kavanozu ve önbellek kapalı, kimlik her istekte elle konan başlıkta.
    private static let sharedSession = makeSession()

    /// Sunucu `Set-Cookie` ile YENİ bir `sessionKey` döndürürse çağrılır.
    ///
    /// Çerez kavanozu bilinçli olarak kapalı; ama claude.ai anahtarı zaman
    /// zaman döndürüyor ve eskisi ölüyor. Kanca olmadan yeni anahtar çöpe
    /// gider, uygulama boşuna "oturum düştü" der. Kavanoz yine kapalı:
    /// yalnızca bu tek çerez, yalnızca claude.ai alanından, çağırana verilir.
    private let onRotatedSessionKey: (@Sendable (String) -> Void)?

    public init(
        sessionKey: String,
        session: URLSession? = nil,
        onRotatedSessionKey: (@Sendable (String) -> Void)? = nil
    ) {
        self.sessionKey = sessionKey
        self.session = session ?? Self.sharedSession
        self.onRotatedSessionKey = onRotatedSessionKey
    }

    /// Çerez claude.ai'nin oturum çerezi mi.
    ///
    /// GÜVENLİK: alan adı `isClaudeCookieDomain` ile denetleniyor. Önceki
    /// `hasSuffix("claude.ai")` denetimi "sahteclaude.ai"yi de kabul ediyordu.
    static func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.name == "sessionKey" && isClaudeCookieDomain(cookie.domain)
    }

    /// Yanıt başlıklarından döndürülmüş oturum anahtarını yakalar.
    private func captureRotatedKey(from http: HTTPURLResponse, url: URL) {
        guard let onRotatedSessionKey,
              let fields = http.allHeaderFields as? [String: String] else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard let rotated = cookies.first(where: Self.isSessionCookie) else { return }
        let value = rotated.value
        guard Self.isPlausibleSessionKey(value), value != sessionKey else { return }
        onRotatedSessionKey(value)
    }

    // MARK: - Uç noktalar

    /// Kullanıcının organizasyon kimliği. Kullanım ucu bunu gerektiriyor.
    public func organizationID() async throws -> String {
        let data = try await request("/api/organizations", accepting: 200...200)
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

    /// Ham usage yanıtı. `usage` da bunun üstünde ayrıştırır.
    ///
    /// limitcheck tanılaması için: alan adları hesaba göre değiştiğinden
    /// neyin geldiğini gözle görmek gerekebiliyor.
    public func rawUsage(organizationID: String) async throws -> Data {
        try await request("/api/organizations/\(organizationID)/usage", accepting: 200...200)
    }

    public func usage(organizationID: String) async throws -> ServerUsage {
        let data = try await rawUsage(organizationID: organizationID)
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
        guard let data = try? await request("/api/organizations/\(organizationID)/prepaid/credits", accepting: 200...200),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Balance(json: root)
    }

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

        _ = try await request(
            base, method: "POST",
            body: ["uuid": conversationID, "name": ""],
            accepting: 200...299
        )

        // Tek kelimelik istem, en ucuz model: amaç cevap değil, pencerenin
        // açılması. Yanıt akış (SSE) olarak dönüyor, gövdesi okunmuyor.
        // Pencereyi açan bu istek; hatası yutulursa pencere açılmadığı halde
        // "başlatıldı" sanılır. Model reddedilirse (hesapta yoksa ya da adı
        // değiştiyse) hesabın varsayılan modeliyle bir kez daha denenir.
        let completion = "\(base)/\(conversationID)/completion"
        var prompt = ["prompt": "hi", "timezone": TimeZone.current.identifier]
        var completionError: Error?
        do {
            prompt["model"] = Self.cheapestModel
            _ = try await request(completion, method: "POST", body: prompt, timeout: 30, accepting: 200...299)
        } catch {
            prompt["model"] = nil
            do {
                _ = try await request(completion, method: "POST", body: prompt, timeout: 30, accepting: 200...299)
            } catch {
                completionError = error
            }
        }

        // Temizlik en iyi çaba: silme başarısız olsa bile pencere açıldı.
        _ = try? await request("\(base)/\(conversationID)", method: "DELETE", body: nil, accepting: 200...299)

        if let completionError { throw completionError }
    }

    /// Pencereyi açmak için kullanılan model. En ucuz/en hızlı olan seçiliyor:
    /// amaç bir cevap almak değil, sayacı başlatmak.
    static let cheapestModel = "claude-haiku-4-5-20251001"

    // MARK: - Taşıma

    /// Tüm istekler buradan geçer: Cloudflare'e duyarlı başlık ve çerez
    /// kuralları GET'i de POST/DELETE'i de aynı yerde kurar.
    ///
    /// `method` nil ise yöntem ve gövde hiç konmaz (varsayılan GET).
    @discardableResult
    private func request(
        _ path: String,
        method: String? = nil,
        body: [String: String]? = nil,
        timeout: TimeInterval = 15,
        accepting ok: ClosedRange<Int>
    ) async throws -> Data {
        guard var components = URLComponents(string: "https://\(Self.host)") else {
            throw ClientError.transport("adres kurulamadı")
        }
        components.path = path
        guard let url = components.url else {
            throw ClientError.transport("adres kurulamadı")
        }

        var request = URLRequest(url: url)
        if let method {
            request.httpMethod = method
        }
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Kimlik YALNIZCA elle konan başlıktan gelsin: kavanoz devrede olsaydı
        // iki kaynak çakışır ve hangisinin gittiği belirsizleşirdi.
        request.httpShouldHandleCookies = false
        for (name, value) in Self.headers(sessionKey: sessionKey) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if method != nil, let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.transportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(-1)
        }
        captureRotatedKey(from: http, url: url)
        switch http.statusCode {
        case ok: return data
        // Cloudflare 401 ile doğrulama yapmıyor, bu koşulsuz oturum sorunudur.
        case 401: throw ClientError.sessionExpired
        case 403: throw Self.classifyForbidden(response: http, body: data)
        default: throw ClientError.badResponse(http.statusCode)
        }
    }

    /// Taşıma hatasını sınıflar. İptal `.transport` DEĞİL: yerine yeni istek
    /// başlatıldığında ya da çıkışta iptal edilen istek geçici ağ hatası
    /// sayılırsa kısa denemeler tetiklenir ve bunlar da uçuştaki yavaş
    /// isteği iptal edip geri çekilmeye kadar giden bir döngü kurar.
    static func transportError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let url = error as? URLError, url.code == .cancelled { return CancellationError() }
        return ClientError.transport(error.localizedDescription)
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
