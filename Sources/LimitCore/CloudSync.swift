import Foundation

/// Bulut senkron kimliği.
///
/// Hesap değil, cihaz kimliği: kullanıcıdan e-posta veya parola istenmiyor.
/// Gizli anahtar yalnızca bu cihazın kendi verisine yazma yetkisi veriyor,
/// Claude hesabıyla hiçbir ilgisi yok.
public struct CloudIdentity: Codable, Sendable, Equatable {
    public let deviceID: String
    public let secret: String

    public var bearer: String { "\(deviceID).\(secret)" }
}

/// Cihaz kimliğini ve yükleme işaretini diskte tutar.
public struct CloudStore: Sendable {
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude Limit/cloud.json")
    }

    private struct State: Codable {
        var identity: CloudIdentity?
        /// En son buluta yazılan örneğin zamanı. Her seferinde baştan
        /// göndermemek için.
        var uploadedThrough: Date?
        /// Verinin bağlı olduğu hesap anahtarı. nil ise veri anonim, yalnızca
        /// bu cihaza ait. Giriş yapıldığında doluyor ve o andan sonra kanonik
        /// sahip hesap oluyor.
        var accountKey: String?
    }

    public let url: URL

    public init(url: URL = CloudStore.defaultURL) {
        self.url = url
    }

    private func load() -> State {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    private func write(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public var identity: CloudIdentity? { load().identity }
    public var uploadedThrough: Date? { load().uploadedThrough }
    public var accountKey: String? { load().accountKey }

    public func save(identity: CloudIdentity) {
        var state = load()
        state.identity = identity
        write(state)
    }

    public func save(uploadedThrough: Date) {
        var state = load()
        state.uploadedThrough = uploadedThrough
        write(state)
    }

    /// Hesap anahtarını yazar. nil vermek hesabı bırakır (çıkış).
    public func save(accountKey: String?) {
        var state = load()
        state.accountKey = accountKey
        write(state)
    }

    /// Yükleme işaretini sıfırlar.
    ///
    /// Hesap benimsendiğinde bir kez çağrılıyor: daha önce hiç yüklenmemiş
    /// yerel satırlar (senkron kapalıyken birikenler, başarısız yüklemeler)
    /// da hesabın altına gitsin. Yükleme idempotent olduğu için tekrar
    /// göndermek güvenli.
    public func resetWatermark() {
        var state = load()
        state.uploadedThrough = nil
        write(state)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Bulut senkron istemcisi.
///
/// Buraya yalnızca kullanım yüzdeleri gidiyor: zaman damgası, 5 saatlik yüzde,
/// haftalık yüzde ve ekstra kullanım yüzdesi. claude.ai oturum anahtarı,
/// e-posta, token sayıları ve proje bilgileri ASLA gönderilmiyor.
///
/// Giriş yapıldığında bir de hesap anahtarı gidiyor: organizasyon kimliğinin
/// geri döndürülemez özeti. Ham kimlik değil özeti gittiği için sunucu hesabı
/// tanımıyor, ama aynı hesap her cihazda aynı anahtarı ürettiği için geçmiş
/// cihaz değiştirince kaybolmuyor. Bkz. `AccountKey`.
///
/// Bulut kaynak değil kopya: yerel arşiv kaynak olmaya devam ediyor, servis
/// düşerse uygulama etkilenmiyor.
public struct CloudSync: Sendable {
    public enum SyncError: Error, Sendable, Equatable {
        case notRegistered
        case badResponse(Int)
        case transport(String)
    }

    public static let defaultEndpoint = URL(
        string: "https://claudetakip-sync.claudetakip-sync.workers.dev"
    )!

    /// Tek istekte gönderilen en fazla örnek. Sunucu 1000'in üstünü reddediyor.
    static let batchLimit = 500

    public let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = CloudSync.defaultEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// Yeni cihaz kaydı. Kullanıcı hiçbir şey yapmıyor.
    public func register() async throws -> CloudIdentity {
        let data = try await send(path: "/v1/devices", method: "POST", identity: nil, body: nil)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceID = root["deviceId"] as? String,
              let secret = root["secret"] as? String
        else { throw SyncError.transport("kayıt yanıtı okunamadı") }
        return CloudIdentity(deviceID: deviceID, secret: secret)
    }

    /// Örnekleri yükler, gerçekten eklenen satır sayısını döner.
    @discardableResult
    public func upload(
        _ samples: [QuotaSample],
        plan: String?,
        identity: CloudIdentity,
        accountKey: String? = nil
    ) async throws -> Int {
        guard !samples.isEmpty else { return 0 }

        var inserted = 0
        // Büyük geçmiş tek istekte gönderilemiyor; parçalara bölünüyor.
        for chunk in stride(from: 0, to: samples.count, by: Self.batchLimit) {
            let slice = Array(samples[chunk..<min(chunk + Self.batchLimit, samples.count)])
            let payload: [String: Any] = [
                "plan": plan as Any,
                "samples": slice.map { sample in
                    [
                        "t": Int(sample.date.timeIntervalSince1970 * 1000),
                        "fiveHour": sample.fiveHour,
                        "sevenDay": sample.sevenDay,
                        "extra": sample.extraUsage as Any,
                    ]
                },
            ]
            let body = try? JSONSerialization.data(withJSONObject: payload)
            let data = try await send(path: "/v1/samples", method: "POST", identity: identity,
                                      body: body, accountKey: accountKey)
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let count = root["inserted"] as? Int {
                inserted += count
            }
        }
        return inserted
    }

    /// Buluttaki geçmişi indirir. Yeni bir makinede arşivi geri yüklemek için.
    ///
    /// `accountKey` verilirse hesabın TÜM cihazlarındaki geçmiş gelir; nil ise
    /// yalnızca bu cihazın anonim verisi.
    public func download(
        since: Date,
        identity: CloudIdentity,
        accountKey: String? = nil
    ) async throws -> [QuotaSample] {
        // Sunucu yanıtı sayfalı: tek istek TÜM geçmişi getirmiyor.
        //
        // Eskiden burada tek bir istek vardı ve `limit` gönderilmiyordu.
        // Sunucunun varsayılanı 5000 ve sıralama `t ASC` olduğu için, geçmiş
        // 5000 satırı aştığında geri yükleme sessizce EN ESKİ 5000 satırı
        // alıyor, kullanıcının son haftaları hiç gelmiyordu. Yerel arşiv bu
        // eşiği çoktan aştı.
        var millis = Int(since.timeIntervalSince1970 * 1000)
        var collected: [QuotaSample] = []
        // Sonsuz döngüye karşı sert tavan: bozuk bir sunucu yanıtı (hasMore
        // hep true, nextSince ilerlemiyor) uygulamayı kilitlemesin.
        let pageLimit = 10000
        for _ in 0..<50 {
            let data = try await send(
                path: "/v1/samples?since=\(millis)&limit=\(pageLimit)",
                method: "GET",
                identity: identity,
                body: nil,
                accountKey: accountKey
            )
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root["samples"] as? [[String: Any]]
            else { break }

            collected.append(contentsOf: rows.compactMap { row in
                guard let t = row["t"] as? Double,
                      let fiveHour = row["fiveHour"] as? Int,
                      let sevenDay = row["sevenDay"] as? Int
                else { return nil }
                return QuotaSample(
                    date: Date(timeIntervalSince1970: t / 1000),
                    org: "cloud",
                    fiveHour: fiveHour,
                    sevenDay: sevenDay,
                    extraUsage: row["extra"] as? Int
                )
            })

            // Eski sunucu sürümü bu alanları döndürmüyor: o zaman tek sayfa
            // davranışı korunuyor, istemci yeni alan yokken kırılmıyor.
            let hasMore = root["hasMore"] as? Bool ?? false
            guard hasMore, let next = root["nextSince"] as? Double, Int(next) > millis else { break }
            millis = Int(next)
        }
        return collected
    }

    public struct Summary: Sendable, Equatable {
        public let count: Int
        public let oldest: Date?
        public let newest: Date?
    }

    public func summary(identity: CloudIdentity, accountKey: String? = nil) async throws -> Summary {
        let data = try await send(path: "/v1/summary", method: "GET", identity: identity,
                                  body: nil, accountKey: accountKey)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.transport("özet okunamadı")
        }
        func date(_ key: String) -> Date? {
            (root[key] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        return Summary(
            count: root["count"] as? Int ?? 0,
            oldest: date("oldest"),
            newest: date("newest")
        )
    }

    /// Bu cihazın anonim satırlarını hesaba devreder.
    ///
    /// Case 1'in çekirdeği: giriş öncesi anonim olarak yüklenmiş geçmiş,
    /// giriş anında hesabın kovasına taşınıyor. Yalnızca `account_key IS NULL`
    /// olan satırlara dokunuyor, yani başka bir hesabın verisi devralınamıyor.
    /// Devredilen satır sayısını döner.
    @discardableResult
    public func claim(identity: CloudIdentity, accountKey: String) async throws -> Int {
        let data = try await send(path: "/v1/claim", method: "POST", identity: identity,
                                  body: Data("{}".utf8), accountKey: accountKey)
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (root?["claimed"] as? Int) ?? 0
    }

    /// Cihazın buluttaki tüm verisini siler.
    /// Buluttaki veriyi siler ve GERÇEKTEN silinen satır sayısını döndürür.
    ///
    /// `accountKey` şart: girişliyken satırların tamamı hesap anahtarıyla
    /// etiketli, başlık gönderilmezse sunucu yalnızca anonim satırları siliyor
    /// ve kullanıcının verisi olduğu gibi kalıyordu. Üstelik istemci hemen
    /// ardından cihaz kimliğini attığı için o veri kalıcı olarak yetim
    /// kalıyordu: sahibi artık kimse değil.
    @discardableResult
    public func deleteEverything(identity: CloudIdentity, accountKey: String? = nil) async throws -> Int {
        let data = try await send(
            path: "/v1/device",
            method: "DELETE",
            identity: identity,
            body: nil,
            accountKey: accountKey
        )
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (root?["removed"] as? Int) ?? 0
    }

    // MARK: - Taşıma

    private func send(
        path: String,
        method: String,
        identity: CloudIdentity?,
        body: Data?,
        accountKey: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: endpoint.absoluteString + path) else {
            throw SyncError.transport("adres kurulamadı")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if let identity {
            request.setValue("Bearer \(identity.bearer)", forHTTPHeaderField: "authorization")
        }
        // Adres olarak başlıkta: sorgu dizesine yazmak onu günlüklere ve
        // yönlendirme geçmişine düşürürdü.
        if let accountKey, AccountKey.isValid(accountKey) {
            request.setValue(accountKey, forHTTPHeaderField: "x-account-key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.badResponse(-1)
        }
        // 401 kimliğin artık geçerli olmadığını söylüyor: cihaz kaydı silinmiş
        // olabilir, yeniden kaydolmak gerekiyor.
        guard http.statusCode == 200 else {
            throw http.statusCode == 401
                ? SyncError.notRegistered
                : SyncError.badResponse(http.statusCode)
        }
        return data
    }
}
