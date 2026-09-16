import Foundation

/// Kullanıcının abonelik bilgisi.
public struct Account: Sendable, Equatable {
    public let displayName: String?
    public let email: String?
    /// Gösterime hazır plan adı: "Max 5x", "Max 20x", "Pro", "Team".
    public let planLabel: String
    public let subscriptionStart: Date?
    public let hasExtraUsage: Bool
    /// Ekstra kullanım kapalıysa sebebi, örneğin `org_level_disabled`.
    public let extraUsageDisabledReason: String?
    /// Hesap profilinin sunucudan en son ne zaman çekildiği.
    ///
    /// Kritik: bu dosya sürekli yeniden yazılıyor ama `oauthAccount` bölümü
    /// yalnızca profil yeniden çekildiğinde tazeleniyor. Dosyanın değişim
    /// zamanına bakıp "bu bilgi güncel" demek yanlış olur.
    public let profileFetchedAt: Date?

    /// Profil bilgisi bu süreden eskiyse üzerine kesin konuşulmaz.
    public var isProfileStale: Bool {
        guard let profileFetchedAt else { return true }
        return Date().timeIntervalSince(profileFetchedAt) > 2 * 3600
    }

    /// Sebebin okunabilir karşılığı. Tanınmayan kod olduğu gibi gösterilir,
    /// çünkü uydurma bir açıklama sessiz kalmaktan kötü.
    public var extraUsageDisabledText: String? {
        switch extraUsageDisabledReason {
        case nil: nil
        case "org_level_disabled": L.t("organizasyon düzeyinde kapalı", "disabled at organization level")
        case "org_level_disabled_until": L.t("organizasyon düzeyinde geçici olarak kapalı", "temporarily disabled at organization level")
        case "user_level_disabled": L.t("hesap düzeyinde kapalı", "disabled at account level")
        case "not_eligible": L.t("bu plan için kullanılamıyor", "not available on this plan")
        case let other?: other
        }
    }

    /// Bir sonraki yenilenme tarihi.
    ///
    /// Yerel veride gerçek yenilenme tarihi YOK. Bu değer aboneliğin başladığı
    /// günden türetiliyor: aylık Stripe aboneliği her ay aynı gün yenilenir.
    /// Kullanıcı yıllık faturaya geçtiyse veya plan değiştirdiyse yanılır,
    /// bu yüzden arayüzde tahmini olduğu belirtilir.
    public var inferredRenewal: Date? {
        guard let subscriptionStart else { return nil }
        let calendar = Calendar.current
        let day = calendar.component(.day, from: subscriptionStart)
        let now = Date()

        for monthOffset in 0...2 {
            guard let base = calendar.date(byAdding: .month, value: monthOffset, to: now),
                  let candidate = calendar.date(
                      bySetting: .day,
                      value: min(day, calendar.range(of: .day, in: .month, for: base)?.count ?? day),
                      of: base
                  )
            else { continue }
            if candidate > now { return candidate }
        }
        return nil
    }
}

/// Claude Desktop'ın hesap bilgisini tuttuğu dosyayı okur.
///
/// Kota dosyası gibi bu da salt okunur ve kimlik bilgisi içermez: yalnızca
/// hangi planda olunduğunu ve aboneliğin ne zaman başladığını söyler.
public struct AccountReader: Sendable {
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    }

    public let url: URL

    public init(url: URL = AccountReader.defaultURL) {
        self.url = url
    }

    public func read() -> Account? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any]
        else { return nil }

        return Account(
            displayName: oauth["displayName"] as? String,
            email: oauth["emailAddress"] as? String,
            planLabel: Self.planLabel(
                rateLimitTier: oauth["organizationRateLimitTier"] as? String,
                organizationType: oauth["organizationType"] as? String
            ),
            subscriptionStart: (oauth["subscriptionCreatedAt"] as? String).flatMap(Self.parseDate),
            hasExtraUsage: oauth["hasExtraUsageEnabled"] as? Bool ?? false,
            // Sebep kodu hesap nesnesinde değil, dosyanın kökünde duruyor.
            extraUsageDisabledReason: root["cachedExtraUsageDisabledReason"] as? String,
            profileFetchedAt: (oauth["profileFetchedAt"] as? Double).map {
                Date(timeIntervalSince1970: $0 / 1000)
            }
        )
    }

    /// Plan adı önce hız limiti kademesinden okunur, çünkü Max 5x ile Max 20x
    /// ayrımını yalnızca o taşıyor. Kademe tanınmazsa organizasyon tipine düşülür.
    static func planLabel(rateLimitTier: String?, organizationType: String?) -> String {
        switch rateLimitTier {
        case "default_claude_max_5x": return "Max 5x"
        case "default_claude_max_20x": return "Max 20x"
        case "default_claude_pro": return "Pro"
        default: break
        }
        switch organizationType {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return "Bilinmiyor"
        }
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
