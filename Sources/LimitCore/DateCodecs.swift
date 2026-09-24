import Foundation

/// claude.ai ve Claude Code'un ISO-8601 zamanları: önce kesirli saniye, olmazsa kesirsiz.
enum ISO8601Parsing {
    /// Biçimleyici her çağrıda yeniden kuruluyor: `ISO8601DateFormatter`
    /// Sendable değil, paylaşılan bir örnek eşzamanlılık denetimine takılır.
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// SQLite anahtarı, bulut yükü ve Claude Desktop dosyası zamanı Unix
/// milisaniyesi olarak tutar; dönüşüm aşağı KESER (yuvarlamaz).
extension Date {
    init(epochMilliseconds ms: Double) {
        self.init(timeIntervalSince1970: ms / 1000)
    }

    var epochMilliseconds: Int64 {
        Int64(timeIntervalSince1970 * 1000)
    }
}
