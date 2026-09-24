import Foundation

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

    /// İndirmede sayfa başına istenen satır.
    static let downloadPageSize = 10_000

    /// Sonsuz döngüye karşı sert tavan: bozuk bir sunucu yanıtı (hasMore
    /// hep true, nextSince ilerlemiyor) uygulamayı kilitlemesin.
    static let maxDownloadPages = 50

    /// Yükleme gövdesi. Codable DEĞİL, JSONSerialization: nil plan ve nil
    /// `extra` açıkça `null` olarak gider.
    static func uploadBody(_ slice: [QuotaSample], plan: String?) -> Data? {
        let payload: [String: Any] = [
            "plan": plan as Any,
            "samples": slice.map { sample in
                [
                    "t": Int(sample.date.epochMilliseconds),
                    "fiveHour": sample.fiveHour,
                    "sevenDay": sample.sevenDay,
                    "extra": sample.extraUsage as Any,
                ]
            },
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// İndirme sayfası. Okunamazsa nil.
    ///
    /// `next` yalnızca `hasMore == true` ve `nextSince` varken dolu; ilerleyip
    /// ilerlemediği çağıranın kararı. Eski sunucu sürümü bu alanları
    /// döndürmüyor: o zaman tek sayfa davranışı korunuyor, istemci yeni alan
    /// yokken kırılmıyor.
    static func parsePage(_ data: Data) -> (samples: [QuotaSample], next: Int?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["samples"] as? [[String: Any]]
        else { return nil }

        let samples: [QuotaSample] = rows.compactMap { row in
            guard let t = row["t"] as? Double,
                  let fiveHour = row["fiveHour"] as? Int,
                  let sevenDay = row["sevenDay"] as? Int
            else { return nil }
            return QuotaSample(
                date: Date(epochMilliseconds: t),
                org: "cloud",
                fiveHour: fiveHour,
                sevenDay: sevenDay,
                extraUsage: row["extra"] as? Int
            )
        }

        let hasMore = root["hasMore"] as? Bool ?? false
        guard hasMore, let next = root["nextSince"] as? Double else { return (samples, nil) }
        return (samples, Int(next))
    }

    let endpoint: URL
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
            let body = Self.uploadBody(slice, plan: plan)
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
        // Sunucu varsayılanı 5000 satır ve `t ASC`; limit ve sayfalama olmadan
        // en ESKİ satırlar gelir, son haftalar hiç gelmez.
        var millis = Int(since.epochMilliseconds)
        var collected: [QuotaSample] = []
        for _ in 0..<Self.maxDownloadPages {
            let data = try await send(
                path: "/v1/samples?since=\(millis)&limit=\(Self.downloadPageSize)",
                method: "GET",
                identity: identity,
                body: nil,
                accountKey: accountKey
            )
            guard let page = Self.parsePage(data) else { break }
            collected.append(contentsOf: page.samples)

            guard let next = page.next, next > millis else { break }
            millis = next
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
            (root[key] as? Double).map { Date(epochMilliseconds: $0) }
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

    /// Buluttaki veriyi siler ve GERÇEKTEN silinen satır sayısını döndürür.
    ///
    /// `accountKey` şart: girişliyken satırların tamamı hesap anahtarıyla
    /// etiketli, başlık gönderilmezse sunucu yalnızca anonim satırları siler
    /// ve kullanıcının verisi olduğu gibi kalır. İstemci hemen ardından cihaz
    /// kimliğini attığı için o veri kalıcı olarak yetim kalır.
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
