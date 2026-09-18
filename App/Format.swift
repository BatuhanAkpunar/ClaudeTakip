import Foundation
import LimitCore

enum Format {
    /// Biçimlendirme dili takip etmeli: İngilizce arayüzde "5 Eyl" ya da
    /// "13,83" yazmak yarım çeviri olurdu.
    private static var locale: Locale { L.locale }

    /// Menü çubuğu için kısa biçim: "3 sa 34 dk" değil "3s 34d".
    ///
    /// Saat ve dakika arasındaki boşluk okunabilirlik için şart: "3s34d" tek bir
    /// belirsiz sayı bloğu gibi okunuyor.
    /// Menü çubuğu geri sayımı: "4:28", "0:07". Saat:dakika, kompakt.
    /// Menü çubuğu için haftalık geri sayım: gün varsa "6g 4s", yoksa saat:dakika.
    /// Saat sıfırsa yalnız gün ("6g"): menü çubuğunda her karakter yer.
    static func compactCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        guard hours >= 24 else { return clockCountdown(interval) }
        let days = hours / 24, rest = hours % 24
        if rest == 0 { return L.t("\(days)g", "\(days)d") }
        return L.t("\(days)g \(rest)s", "\(days)d \(rest)h")
    }

    static func clockCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return "\(total / 3600):\(String(format: "%02d", (total % 3600) / 60))"
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return L.t("\(hours)s \(minutes)d", "\(hours)h \(minutes)m") }
        return L.t("\(minutes)d", "\(minutes)m")
    }

    /// Popover için okunur biçim: "3 sa 34 dk".
    static func duration(_ interval: TimeInterval) -> String {
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
    static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: roundedToMinute(date))
    }

    /// Başlık yanındaki mutlak sıfırlanma anı: "23 Ağu 01:39".
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        // Gün-ay sırası dile bağlı: "23 Ağu" karşılığı İngilizcede "Aug 23".
        formatter.dateFormat = L.t("d MMM HH:mm", "MMM d HH:mm")
        return formatter.string(from: date)
    }

    /// Tahmini bitiş damgası: "25.08.2026 08:10".
    static func fullStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = L.t("dd.MM.yyyy HH:mm", "MM/dd/yyyy HH:mm")
        return formatter.string(from: date)
    }

    /// Başlıktaki tazelik göstergesi: "şimdi", "1 dk", "10 dk", "2 sa".
    static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return L.t("şimdi", "just now") }
        if seconds < 3600 { return L.t("\(seconds / 60) dk", "\(seconds / 60)m") }
        return L.t("\(seconds / 3600) sa", "\(seconds / 3600)h")
    }

    /// Abonelik yenilenme tarihi: "8 Eyl".
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = L.t("d MMM", "MMM d")
        return formatter.string(from: date)
    }

    /// Grafik ekseni, haftalık pencere: "15 Ağu".
    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = L.t("d MMM", "MMM d")
        return formatter.string(from: date)
    }

    /// Yalnızca gün numarası, ay adı olmadan: "29". Haftalık eksende her gün
    /// için ayrı tık gösterilirken "29 Ağu, 30 Ağu, 31 Ağu..." sığmıyordu; ay
    /// yalnızca değiştiği tıkta yazılıyor, aradakiler bu kısa hâle düşüyor.
    static func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    /// Kısa gün adı: "Cmt", "Paz". Haftalık eksende iç işaretler için;
    /// uçlardaki tam tarihin (29 Ağu) aksine hafta içindeki günü anlatıyor.
    static func weekdayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Ondalık ayracı dile bağlı: TR virgül, EN nokta.
    private static func decimal(_ formatted: String) -> String {
        L.isTurkish ? formatted.replacingOccurrences(of: ".", with: ",") : formatted
    }

    /// Para tutarı: "$13,83". Sunucudan sent geldiği için çevrim istemcide yapılıyor.
    static func money(_ value: Double, currency: String = "USD") -> String {
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
    static func multiplier(_ value: Double) -> String {
        let oneDecimal = (value * 10).rounded() / 10
        guard oneDecimal == 1, value != 1 else {
            return decimal(String(format: "%.1f×", oneDecimal))
        }
        let twoDecimals = value < 1
            ? (value * 100).rounded(.down) / 100
            : (value * 100).rounded(.up) / 100
        return decimal(String(format: "%.2f×", twoDecimals))
    }

    // MARK: - Sıfırlanma cümlesi

    /// Türkçede bulunma hâli eki: sondaki ünlü kalın mı ince mi, son ünsüz
    /// sert mi yumuşak mı. On iki ay adının hepsini doğru veriyor
    /// (Ocakta, Şubatta, Martta, Nisanda, Mayısta, Haziranda, Temmuzda,
    /// Ağustosta, Eylülde, Ekimde, Kasımda, Aralıkta).
    private static func locativeSuffix(for word: String) -> String {
        let lower = word.lowercased(with: Locale(identifier: "tr_TR"))
        let back: Set<Character> = ["a", "ı", "o", "u"]
        let front: Set<Character> = ["e", "i", "ö", "ü"]
        let voiceless: Set<Character> = ["f", "s", "t", "k", "ç", "ş", "h", "p"]
        var isBack = true
        for ch in lower.reversed() where back.contains(ch) || front.contains(ch) {
            isBack = back.contains(ch)
            break
        }
        let hard = lower.last.map { voiceless.contains($0) } ?? false
        switch (isBack, hard) {
        case (true, true): return "ta"
        case (true, false): return "da"
        case (false, true): return "te"
        case (false, false): return "de"
        }
    }

    /// Sayının okunuşuna göre bulunma eki. Saat ve dakika için: 10 → "onda",
    /// 40 → "kırkta", 05 → "beşte". Bileşik sayılarda eki SON sözcük veriyor
    /// ("on bir" → "on birde"), o yüzden birler basamağı varsa o belirliyor.
    private static func numberLocative(_ n: Int) -> String {
        let ones = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
        let tens = ["", "on", "yirmi", "otuz", "kırk", "elli"]
        let word: String
        if n >= 10, n % 10 != 0 { word = ones[n % 10] }
        else if n >= 10 { word = tens[min(n / 10, 5)] }
        else { word = ones[n] }
        return locativeSuffix(for: word)
    }

    /// "19 Eylülde sıfırlanır" / "19 Eylül 10:00da sıfırlanır".
    ///
    /// Tasarımda sıfırlanma bilgisi kısaltma değil TAM CÜMLE. Türkçede ek
    /// tarihin son sözcüğüne göre değiştiği için düz birleştirme yanlış
    /// sonuç veriyor ("19 Eylülda"), bu yüzden ek hesaplanıyor.
    static func resetSentence(_ rawDate: Date, includeTime: Bool) -> String {
        // Gün, saat ve ek AYNI yuvarlanmış andan: yoksa 23:59:59'da gün eski,
        // saat yeni günden okunurdu.
        let date = roundedToMinute(rawDate)
        let month = DateFormatter()
        month.locale = locale
        month.dateFormat = L.t("d MMMM", "d MMMM")
        let day = month.string(from: date)

        guard L.isTurkish else {
            return includeTime
                ? "Resets \(day) at \(hourLabel(date))"
                : "Resets on \(day)"
        }

        if includeTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let hour = parts.hour ?? 0, minute = parts.minute ?? 0
            let suffix = numberLocative(minute != 0 ? minute : hour)
            return "\(day) \(hourLabel(date))\(suffix) sıfırlanır"
        }
        // Ay adı son sözcük: eki o veriyor.
        let name = day.split(separator: " ").last.map(String.init) ?? day
        return "\(day)\(locativeSuffix(for: name)) sıfırlanır"
    }

    /// Yalnız saat: 5 saatlik pencerede tarih yazmak gürültü.
    static func resetSentenceTimeOnly(_ rawDate: Date) -> String {
        let date = roundedToMinute(rawDate)
        guard L.isTurkish else { return "Resets at \(hourLabel(date))" }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let suffix = numberLocative((parts.minute ?? 0) != 0 ? (parts.minute ?? 0) : (parts.hour ?? 0))
        return "\(hourLabel(date))\(suffix) sıfırlanır"
    }
}
