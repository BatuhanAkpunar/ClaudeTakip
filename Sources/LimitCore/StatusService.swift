import Foundation

/// status.claude.com'un bildirdiği servis durumu.
public enum ServiceStatus: String, Sendable {
    case operational
    case minor
    case major
    case critical
    case unknown

    /// Statuspage'in indicator alanı: none, minor, major, critical.
    init(indicator: String) {
        switch indicator {
        case "none": self = .operational
        case "minor": self = .minor
        case "major": self = .major
        case "critical": self = .critical
        default: self = .unknown
        }
    }

    public var isHealthy: Bool { self == .operational }
}

public struct ServiceStatusReport: Sendable, Equatable {
    public let status: ServiceStatus
    /// Statuspage'in kendi açıklaması, örneğin "All Systems Operational".
    public let description: String
    public let checkedAt: Date

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.status == rhs.status && lhs.description == rhs.description
    }
}

/// Claude servis durumunu sorgular.
///
/// Bu, uygulamanın yaptığı tek ağ isteği. Kimlik doğrulama gerektirmeyen,
/// herkese açık bir Statuspage uç noktası: kota verisinin aksine burada
/// kullanıcıya ait hiçbir şey gidip gelmiyor.
public struct StatusService: Sendable {
    public static let endpoint = URL(string: "https://status.claude.com/api/v2/status.json")!

    public init() {}

    public func fetch() async -> ServiceStatusReport? {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusObject = root["status"] as? [String: Any]
        else { return nil }

        return ServiceStatusReport(
            status: ServiceStatus(indicator: statusObject["indicator"] as? String ?? ""),
            description: statusObject["description"] as? String ?? "",
            checkedAt: Date()
        )
    }
}
