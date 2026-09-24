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
    /// Her saat kaç ayrı günde gözlemlendi. Az gözlemli saatler zayıf kanıt.
    public let hourSampleDays: [Int]
    /// Profilin dayandığı toplam gün sayısı.
    public let observedDays: Int

    public var peakHour: Int? {
        guard let maximum = hourly.max(), maximum > 0 else { return nil }
        return hourly.firstIndex(of: maximum)
    }

    /// Profil güvenilir sayılacak kadar gözlem var mı.
    ///
    /// Üç günün altında saatlik desen gürültüden ibaret oluyor: tek bir yoğun
    /// gece bütün profili o saate kaydırıyor.
    public var isReliable: Bool { observedDays >= 3 }

    public static let empty = UsageProfile(
        hourly: Array(repeating: 0, count: 24),
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
        // KAPSAM: o saatin gözlendiği günler. Tüketim olsun olmasın
        // sayılıyor. Paydalar için aşağıya bakın.
        var hourCoverage: [Set<DateComponents>] = Array(repeating: [], count: 24)
        var allDays: Set<DateComponents> = []

        for (previous, current) in zip(samples, samples.dropFirst()) {
            // Uzun boşluk gerçek çalışma değil, uygulamanın kapalı olduğu zaman.
            // O aralığa düşen artışı tek bir saate yazmak profili bozardı.
            let gap = current.date.timeIntervalSince(previous.date)
            guard gap > 0, gap <= 3600 else { continue }

            let day = calendar.dateComponents([.year, .month, .day], from: current.date)
            let hour = calendar.component(.hour, from: current.date)

            // Kapsam önce yazılıyor: sessiz geçen bir saat de gözlenmiştir ve
            // ortalamayı aşağı çekmelidir.
            hourCoverage[hour].insert(day)
            allDays.insert(day)

            let delta = Double(current.fiveHour - previous.fiveHour)
            // Negatif fark sıfırlanma, sıfır fark duruş.
            guard delta > 0 else { continue }

            hourlyTotal[hour] += delta
        }

        // PAYDA, bilinçli:
        //
        // Saatlik profil profildeki TOPLAM güne bölünüyor, "o saatin gözlendiği
        // gün"e değil: her gün 24 saatin hepsini kapsayabilir; gözlenmemiş bir
        // saat "o gün o saatte kullanım olmadı" demek (uygulama giriş öğesi
        // olarak sürekli açık, Mac uykudaysa kullanım da yok). Tüketimin
        // OLDUĞU güne bölmek koşullu bir ortalama (E[X | X > 0]) verir ve nadir
        // ama yoğun bir saati sık ama ılımlı bir saatten yüksek gösterir.
        // Örnek: kullanıcı 20 gün boyunca her öğleden sonra 14:00'te çalışıp
        // bir tek gece 03:00'te patlarsa, saate özel paydayla 03:00 ortalaması
        // 40, 14:00 ortalaması 20 çıkar ve kadran "en yoğun saatin 03:00" der.
        // Sorulan soru ise "rastgele bir günde bu saatte ne kadar harcarım":
        // 03:00 için 40/20 = 2, 14:00 için 400/20 = 20. Tek bir gece görülen
        // değeri her güne yaymak, hiç görmediğini sıfır saymaktan çok daha
        // büyük bir hata üretir.
        //
        // Saatlik paydanın bilinen sınırı: başka bir cihazdan ya da
        // tarayıcıdan kullanılan kota bu makinede hiç görülmüyor ve o saat
        // olduğundan soğuk çıkıyor. Kapsama `hourSampleDays` ile taşınıyor,
        // arayüz ipucunda gösteriliyor.
        let days = Double(max(1, allDays.count))
        let hourly = (0..<24).map { hourlyTotal[$0] / days }

        return UsageProfile(
            hourly: hourly,
            hourSampleDays: (0..<24).map { hourCoverage[$0].count },
            observedDays: allDays.count
        )
    }
}
