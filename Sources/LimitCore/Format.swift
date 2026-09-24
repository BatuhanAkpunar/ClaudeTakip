import Foundation

public enum Format {
    /// Biçimlendirme dili takip etmeli: İngilizce arayüzde "5 Eyl" ya da
    /// "13,83" yazmak yarım çeviri olurdu.
    static var locale: Locale { L.locale }

    /// Tek biçimlendirici tarifi: her çağrıda yeni `DateFormatter`, dil `L.locale`.
    static func string(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Menü çubuğu geri sayımı: "4:28", "0:07". Saat:dakika, kompakt.
    public static func clockCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return "\(total / 3600):\(String(format: "%02d", (total % 3600) / 60))"
    }

    /// Popover için okunur biçim: "3 sa 34 dk".
    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let days = hours / 24
        if days >= 1 {
            let restHours = hours % 24
            if restHours > 0 {
                return L.t("\(days) gün \(restHours) sa", "\(days)d \(restHours)h")
            }
            return L.t("\(days) gün", "\(days)d")
        }
        if hours > 0 { return L.t("\(hours) sa \(minutes) dk", "\(hours)h \(minutes)m") }
        return L.t("\(minutes) dk", "\(minutes)m")
    }

    /// En yakın dakikaya yuvarlar.
    ///
    /// Sunucu sıfırlanma anını saniyesiyle veriyor ve genelde dakikanın hemen
    /// öncesine düşüyor (09:59:59.8). `DateFormatter` saniyeyi KIRPTIĞI için
    /// etiket "09:59da sıfırlanır" yazıyordu; gerçekte kastedilen 10:00.
    /// Kırpmak yerine yuvarlamak, saati de günü de doğru tarafa taşıyor
    /// (23:59:59 → ertesi gün 00:00).
    static func roundedToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    }

    /// Grafik ekseni, 5 saatlik pencere: "14:00". Dakikaya YUVARLANIYOR.
    public static func hourLabel(_ date: Date) -> String {
        string(roundedToMinute(date), pattern: "HH:mm")
    }

    /// Öngörülen aşımın tarih ve saati. Dakikaya YUVARLANIYOR, diğer saat
    /// biçimleriyle aynı: 09:59:59 "09:59" değil "10:00".
    public static func stamp(_ date: Date) -> String {
        // Gün-ay sırası dile bağlı: "23 Ağu" karşılığı İngilizcede "Aug 23".
        string(roundedToMinute(date), pattern: L.t("d MMM HH:mm", "MMM d HH:mm"))
    }

    /// Başlıktaki tazelik göstergesi: "şimdi", "1 dk", "10 dk", "2 sa".
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return L.t("şimdi", "just now") }
        if seconds < 3600 { return L.t("\(seconds / 60) dk", "\(seconds / 60)m") }
        return L.t("\(seconds / 3600) sa", "\(seconds / 3600)h")
    }

    /// Abonelik yenilenme tarihi ve haftalık grafik ekseni: "8 Eyl".
    public static func shortDate(_ date: Date) -> String {
        string(date, pattern: L.t("d MMM", "MMM d"))
    }

    /// Kısa gün adı: "Cmt", "Paz". Haftalık eksende iç işaretler için;
    /// uçlardaki tam tarihin (29 Ağu) aksine hafta içindeki günü anlatıyor.
    public static func weekdayShort(_ date: Date) -> String {
        string(date, pattern: "EEE")
    }

    /// Ondalık ayracı dile bağlı: TR virgül, EN nokta.
    private static func decimal(_ formatted: String) -> String {
        L.isTurkish ? formatted.replacingOccurrences(of: ".", with: ",") : formatted
    }

    /// Para tutarı: "$13,83". Sunucudan sent geldiği için çevrim istemcide yapılıyor.
    public static func money(_ value: Double, currency: String) -> String {
        let symbol = currency == "USD" ? "$" : "\(currency) "
        return symbol + decimal(String(format: "%.2f", value))
    }

    /// Pace: "1,3×". 1 bir EŞİK (üstü = sıfırlanmadan dolar), dolayısıyla
    /// yuvarlama o eşiği asla geçmemeli.
    ///
    /// Tek ondalıkta 0,95 ile 1,05 arasındaki her değer "1,0×" oluyor: 0,96
    /// (dolmayacak) ile 1,04 (dolacak) ekranda aynı görünüyordu. O bantta iki
    /// ondalık gösteriliyor ve eşiğin AYNI tarafına yuvarlanıyor: 1'in altı
    /// aşağı, üstü yukarı. Sapma en fazla 0,01; işaret hiç değişmiyor.
    public static func multiplier(_ value: Double) -> String {
        let oneDecimal = (value * 10).rounded() / 10
        guard oneDecimal == 1, value != 1 else {
            return decimal(String(format: "%.1f×", oneDecimal))
        }
        let twoDecimals = value < 1
            ? (value * 100).rounded(.down) / 100
            : (value * 100).rounded(.up) / 100
        return decimal(String(format: "%.2f×", twoDecimals))
    }

    /// Yüzde etiketi: TR "%83", EN "83%". İşaretin yeri dile bağlı.
    public static func percent(_ value: Double) -> String {
        L.t("%\(Int(value.rounded()))", "\(Int(value.rounded()))%")
    }
}
