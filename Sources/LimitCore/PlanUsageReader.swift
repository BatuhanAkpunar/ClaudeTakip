import Foundation

/// Claude Desktop'ın kendi kota geçmişi dosyasını okur.
///
/// Bu dosya uygulamanın birincil veri kaynağıdır: gerçek sunucu yüzdelerini içerir,
/// hiçbir kimlik bilgisi veya ağ isteği gerektirmez. Claude Desktop dosyayı
/// yaklaşık 5 dakikada bir günceller (kullanıcı makinesinde ölçülen medyan: 300 sn).
public struct PlanUsageReader: Sendable {
    public enum ReadError: Error, Sendable, Equatable {
        case fileNotFound(URL)
        case unreadable(String)
        case malformed(String)
        /// Dosya tanınmayan bir şema sürümüyle yazılmış. Katman B'ye düşülmeli.
        case unsupportedVersion(Int)
    }

    /// Doğrulanmış şema sürümü. Claude Desktop bunu değiştirirse okumayı reddederiz.
    public static let supportedVersion = 2

    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    public let url: URL

    public init(url: URL = PlanUsageReader.defaultURL) {
        self.url = url
    }

    /// Dosyanın son yazılma zamanı. Verinin tazeliği bununla değerlendirilir.
    public func lastModified() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    public func read() throws -> [QuotaSample] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadError.fileNotFound(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ReadError.unreadable(error.localizedDescription)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.malformed("kök nesne okunamadı")
        }
        let version = root["version"] as? Int ?? 0
        guard version == Self.supportedVersion else {
            throw ReadError.unsupportedVersion(version)
        }
        guard let raw = root["samples"] as? [[String: Any]] else {
            throw ReadError.malformed("samples dizisi yok")
        }

        var samples: [QuotaSample] = []
        samples.reserveCapacity(raw.count)
        for entry in raw {
            guard let t = entry["t"] as? Double,
                  let u = entry["u"] as? [String: Any],
                  let fh = u["fh"] as? Int,
                  let sd = u["sd"] as? Int
            else { continue }
            samples.append(QuotaSample(
                date: Date(timeIntervalSince1970: t / 1000),
                org: entry["org"] as? String ?? "",
                fiveHour: fh,
                sevenDay: sd,
                extraUsage: u["xu"] as? Int
            ))
        }
        return samples.sorted { $0.date < $1.date }
    }
}
