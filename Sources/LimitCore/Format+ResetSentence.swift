import Foundation

// MARK: - Sıfırlanma cümlesi

extension Format {
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

    /// Saat ve bulunma eki: "10:00da", "14:40ta". Eki dakika sıfır değilse
    /// dakika, sıfırsa saat veriyor. Verilen an dakikaya yuvarlanmış olmalı.
    static func timeWithLocative(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return "\(hourLabel(date))\(numberLocative(minute != 0 ? minute : hour))"
    }

    /// "19 Eylülde sıfırlanır" / "19 Eylül 10:00da sıfırlanır".
    ///
    /// Tasarımda sıfırlanma bilgisi kısaltma değil TAM CÜMLE. Türkçede ek
    /// tarihin son sözcüğüne göre değiştiği için düz birleştirme yanlış
    /// sonuç veriyor ("19 Eylülda"), bu yüzden ek hesaplanıyor.
    public static func resetSentence(_ rawDate: Date, includeTime: Bool) -> String {
        // Gün, saat ve ek AYNI yuvarlanmış andan: yoksa 23:59:59'da gün eski,
        // saat yeni günden okunurdu.
        let date = roundedToMinute(rawDate)
        // İngilizcede ay önce: `shortDate`'in "Oct 1" sırasıyla aynı.
        let day = string(date, pattern: L.t("d MMMM", "MMMM d"))

        guard L.isTurkish else {
            return includeTime
                ? "Resets \(day) at \(hourLabel(date))"
                : "Resets on \(day)"
        }

        if includeTime {
            return "\(day) \(timeWithLocative(date)) sıfırlanır"
        }
        // Ay adı son sözcük: eki o veriyor.
        let name = day.split(separator: " ").last.map(String.init) ?? day
        return "\(day)\(locativeSuffix(for: name)) sıfırlanır"
    }

    /// Yalnız saat: 5 saatlik pencerede tarih yazmak gürültü.
    public static func resetSentenceTimeOnly(_ rawDate: Date) -> String {
        let date = roundedToMinute(rawDate)
        guard L.isTurkish else { return "Resets at \(hourLabel(date))" }
        return "\(timeWithLocative(date)) sıfırlanır"
    }
}
