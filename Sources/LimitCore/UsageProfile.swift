import Foundation

/// Kullanıcının kota tüketim alışkanlığı.
///
/// Kaynak token sayıları değil, kota yüzdesinin kendisi. Sebebi iki tane:
///
/// 1. Token ile kota orantılı değil. Cache okumaları, model farkları ve
///    düşünme token'ları oranı kaydırıyor; kullanıcıyı durduran şey token
///    değil kota.
/// 2. Token verisi yalnızca Claude Code veya Desktop kullananlarda var.
///    Kota yüzdesi herkeste var, tarayıcıdan kullananlarda bile.
public struct UsageProfile: Sendable, Equatable {
    /// Saat başına ortalama kota tüketimi, yüzde/gün. 0-23.
    public let hourly: [Double]
    /// Haftanın günü başına ortalama tüketim. 1 = Pazar, 7 = Cumartesi.
    public let weekday: [Double]
    /// Her saat kaç ayrı günde gözlemlendi. Az gözlemli saatler zayıf kanıt.
    public let hourSampleDays: [Int]
    /// Profilin dayandığı toplam gün sayısı.
    public let observedDays: Int

    public var peakHour: Int? {
        guard let maximum = hourly.max(), maximum > 0 else { return nil }
        return hourly.firstIndex(of: maximum)
    }

    /// Verilen saatler için beklenen toplam tüketim.
    ///
    /// Tahminin çekirdeği: "önümüzdeki dört saatte, senin bu saatlerdeki
    /// alışkanlığına göre ne kadar harcarsın".
    public func expectedConsumption(hours: [Int]) -> Double {
        hours.reduce(0) { total, hour in
            total + hourly[((hour % 24) + 24) % 24]
        }
    }

    /// Profil güvenilir sayılacak kadar gözlem var mı.
    ///
    /// Üç günün altında saatlik desen gürültüden ibaret oluyor: tek bir yoğun
    /// gece bütün profili o saate kaydırıyor.
    public var isReliable: Bool { observedDays >= 3 }

    public static let empty = UsageProfile(
        hourly: Array(repeating: 0, count: 24),
        weekday: Array(repeating: 0, count: 8),
        hourSampleDays: Array(repeating: 0, count: 24),
        observedDays: 0
    )

    /// Kota örneklerinden profil çıkarır.
    ///
    /// Tüketim, 5 saatlik pencere yüzdesinin pozitif artışlarından okunuyor.
    /// Haftalık pencere de aynı bilgiyi taşıyor ama çözünürlüğü kaba: haftalık
    /// bütçe çok daha büyük olduğu için bir saatlik çalışma çoğu zaman yüzdeyi
    /// hiç oynatmıyor.
    public static func build(
        from samples: [QuotaSample],
        calendar: Calendar = .current
    ) -> UsageProfile {
        guard samples.count > 1 else { return .empty }

        var hourlyTotal = [Double](repeating: 0, count: 24)
        var weekdayTotal = [Double](repeating: 0, count: 8)
        // KAPSAM: o saatin gözlendiği günler. Tüketim olsun olmasın sayılıyor.
        //
        // Önceden payda "tüketimin OLDUĞU gün" idi, yani ortalama koşulluydu:
        // E[X | X > 0]. Bu, nadir ama yoğun bir saati sık ama ılımlı bir saatten
        // yüksek gösteriyordu. 20 gün her akşam 14:00'te çalışan, bir gece
        // 03:00'te patlayan kullanıcıda kadran "en yoğun 03:00" diyordu.
        // Payda artık gözlem sayısı, yani gerçek günlük ortalama.
        var hourCoverage: [Set<DateComponents>] = Array(repeating: [], count: 24)
        var weekdayCoverage: [Set<DateComponents>] = Array(repeating: [], count: 8)
        var allDays: Set<DateComponents> = []

        for (previous, current) in zip(samples, samples.dropFirst()) {
            // Uzun boşluk gerçek çalışma değil, uygulamanın kapalı olduğu zaman.
            // O aralığa düşen artışı tek bir saate yazmak profili bozardı.
            let gap = current.date.timeIntervalSince(previous.date)
            guard gap > 0, gap <= 3600 else { continue }

            let day = calendar.dateComponents([.year, .month, .day], from: current.date)
            let hour = calendar.component(.hour, from: current.date)
            let weekday = calendar.component(.weekday, from: current.date)

            // Kapsam önce yazılıyor: sessiz geçen bir saat de gözlenmiştir ve
            // ortalamayı aşağı çekmelidir.
            hourCoverage[hour].insert(day)
            weekdayCoverage[weekday].insert(day)
            allDays.insert(day)

            let delta = Double(current.fiveHour - previous.fiveHour)
            // Negatif fark sıfırlanma, sıfır fark duruş.
            guard delta > 0 else { continue }

            hourlyTotal[hour] += delta
            weekdayTotal[weekday] += delta
        }

        // Payda: profildeki TOPLAM gün. "O saatin gözlendiği gün" değil.
        //
        // Fark kritik. Kullanıcı 20 gün boyunca her öğleden sonra 14:00'te
        // çalışıp bir tek gece 03:00'te patlarsa, saate özel paydayla 03:00
        // ortalaması 40, 14:00 ortalaması 20 çıkıyor ve kadran "en yoğun saatin
        // 03:00" diyor. Oysa sorulan soru "rastgele bir günde bu saatte ne
        // kadar harcarım": 03:00 için 40/20 = 2, 14:00 için 400/20 = 20.
        //
        // Gözlenmemiş bir saat 0 veriyor. Bu bir varsayım ve dürüst olanı:
        // tek bir gece görülen değeri her güne yaymak, hiç görmediğini sıfır
        // saymaktan çok daha büyük bir hata üretiyor.
        // İKİ FARKLI PAYDA, bilinçli:
        //
        // Saatlik profil TOPLAM güne bölünüyor, çünkü her gün 24 saatin
        // hepsini kapsayabilir; gözlenmemiş bir saat "o gün o saatte kullanım
        // olmadı" demek (uygulama giriş öğesi olarak sürekli açık, Mac
        // uykudaysa kullanım da yok). Haftalık profil ise O HAFTA GÜNÜNÜN
        // sayısına bölünüyor: Pazartesi verisi yalnızca Pazartesilerden gelir,
        // toplam güne bölmek değeri yedide bir gösterirdi.
        //
        // Saatlik paydanın bilinen sınırı: başka bir cihazdan ya da
        // tarayıcıdan kullanılan kota bu makinede hiç görülmüyor ve o saat
        // olduğundan soğuk çıkıyor. Kapsama `hourSampleDays` ile taşınıyor,
        // arayüz ipucunda gösteriliyor.
        let days = Double(max(1, allDays.count))
        let hourly = (0..<24).map { hourlyTotal[$0] / days }
        let weekday = (0..<8).map { index -> Double in
            let observed = weekdayCoverage[index].count
            return observed > 0 ? weekdayTotal[index] / Double(observed) : 0
        }

        return UsageProfile(
            hourly: hourly,
            weekday: weekday,
            hourSampleDays: (0..<24).map { hourCoverage[$0].count },
            observedDays: allDays.count
        )
    }
}
