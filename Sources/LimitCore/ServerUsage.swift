import Foundation

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
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    /// Model bazlı haftalık kotalar, gösterim adıyla eşlenmiş.
    public let modelWindows: [String: Window]
    public let wallet: Wallet?

    /// limitcheck ham yanıtı bir kez çekip aynı gövdeyi ayrıştırabilsin diye public.
    public init(json: [String: Any]) {
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
            let limit = Self.number(extra["monthly_limit"]).map(Self.dollars(fromCents:))
            let spent = Self.number(extra["used_credits"]).map(Self.dollars(fromCents:))
            // Sunucu `is_enabled` alanını her zaman göndermiyor. Yokluğunda
            // "kapalı" varsaymak, tutarları gösterirken "Kapalı" yazan bir kart
            // üretir. Tavan ya da harcama varsa cüzdan zaten açıktır.
            let hasAmounts = (limit ?? 0) > 0 || (spent ?? 0) > 0
            wallet = Wallet(
                isEnabled: extra["is_enabled"] as? Bool ?? hasAmounts,
                // Sıfır tavan "limitsiz" demek, gösterilecek bir sayı değil.
                monthlyLimit: (limit ?? 0) > 0 ? limit : nil,
                usedCredits: spent,
                utilization: Self.number(extra["utilization"]),
                currency: extra["currency"] as? String ?? "USD",
                spendLimitReached: Self.number(extra["spend_limit_reached"]) == 1
                    || (extra["spend_limit_reached"] as? Bool ?? false)
            )
        } else {
            wallet = nil
        }
    }

    private static func window(_ raw: Any?) -> Window? {
        guard let object = raw as? [String: Any] else { return nil }
        // Yüzde alanının adı şemaya göre değişiyor: üst seviye pencerelerde
        // `utilization`, eski sürümlerde `used_percentage`, `limits` dizisinin
        // elemanlarında ise `percent`. Üçü de okunmalı; biri eksik kalırsa o
        // şemadaki kotalar (ör. `percent` için Fable dahil model bazlı
        // kotalar) sessizce elenir.
        guard let value = number(object["utilization"])
            ?? number(object["used_percentage"])
            ?? number(object["percent"])
        else {
            return nil
        }
        return Window(utilization: value, resetsAt: date(object["resets_at"]))
    }

    /// Para alanları SENT cinsinden geliyor: 2050 = 20,50 USD.
    /// Doğrudan göstermek tutarı yüz katına çıkarır.
    static func dollars(fromCents cents: Double) -> Double {
        cents / 100
    }

    static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        return ISO8601Parsing.date(from: text)
    }
}

extension ClaudeWebClient {
    public struct Balance: Sendable, Equatable {
        public let remaining: Double?
        public let autoReloadEnabled: Bool
    }
}

extension ClaudeWebClient.Balance {
    /// `/prepaid/credits` yanıtı. Tutarlar burada da sent cinsinden.
    init?(json root: [String: Any]) {
        self.init(
            remaining: ServerUsage.number(root["amount"]).map(ServerUsage.dollars(fromCents:)),
            autoReloadEnabled: root["auto_reload_settings"] != nil
                && !(root["auto_reload_settings"] is NSNull)
        )
    }
}

extension ServerUsage {
    public func window(for kind: WindowKind) -> Window? {
        switch kind {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }

    /// Adı `name`'i içeren (büyük/küçük harf duyarsız) model kotası.
    public func modelWindow(matching name: String) -> Window? {
        modelWindows.first(where: { $0.key.localizedCaseInsensitiveContains(name) })?.value
    }
}

extension ServerUsage.Window {
    /// Pencere ŞU AN kapalı mı.
    ///
    /// claude.ai `resets_at` alanını yalnızca pencere açıkken döndürüyor;
    /// alan yoksa ya da geçmişteyse pencere kapalı demektir.
    public func isClosed(at now: Date) -> Bool {
        guard let resetsAt else { return true }
        return resetsAt <= now
    }
}

extension ServerUsage.Wallet {
    public var roundedUtilization: Int? { utilization.map { Int($0.rounded()) } }
}
