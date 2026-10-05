import Foundation

/// Kullanıcının kota tüketim alışkanlığı: günün hangi saatlerinde çalışıyor.
///
/// Kaynak token sayıları değil, kota yüzdesinin kendisi. Sebebi iki tane:
///
/// 1. Token ile kota orantılı değil. Cache okumaları, model farkları ve
///    düşünme token'ları oranı kaydırıyor; kullanıcıyı durduran şey token
///    değil kota.
/// 2. Token verisi yalnızca Claude Code veya Desktop kullananlarda var.
///    Kota yüzdesi herkeste var, tarayıcıdan kullananlarda bile.
///
/// ANA ÖLÇÜ SIKLIK, büyüklük değil: "bu saat, Mac'in açık olduğu günlerin
/// kaçında kota harcadı". Büyüklüğe dayalı bir ortalamada tek bir yoğun gece
/// her gün çalışılan saati geçebiliyordu; sıklık "genelde ne zaman
/// çalışırım" sorusunun kendisi. Büyüklük (`intensity`) ayrıntı tablosunda
/// ikinci bilgi olarak duruyor.
public struct UsageProfile: Sendable, Equatable {
    /// Saat başına aktiflik payı, 0-1: o saatin gözlendiği günlerin (yakın
    /// günler ağır basacak şekilde ağırlıklı) kaçında tüketim oldu. 0-23.
    public let hourly: [Double]
    /// Saat başına, tüketim olan günlerde ortalama tüketim (yüzde puanı).
    public let intensity: [Double]
    /// Her saat kaç ayrı günde gözlemlendi. Az gözlemli saatler zayıf kanıt.
    public let hourSampleDays: [Int]
    /// Profilin dayandığı toplam gün sayısı.
    public let observedDays: Int
    /// Hafta günü × saat aktiflik payı (7 × 24). Satır 0 Pazartesi.
    public let weekdayHourly: [[Double]]
    /// Hafta günü × saat gözlenen gün sayısı (7 × 24).
    public let weekdaySampleDays: [[Int]]
    /// Tahmin için haftalık kota puanı / takvim günü. Aktiflik sıklığıyla
    /// karıştırılmaz; büyüklük haftalık sayacın kendisinden gelir.
    public let forecastActiveDays: Int
    public let forecastHourly: [Double]
    public let forecastWeekdayHourly: [[Double]]

    public init(
        hourly: [Double],
        intensity: [Double]? = nil,
        hourSampleDays: [Int],
        observedDays: Int,
        weekdayHourly: [[Double]]? = nil,
        weekdaySampleDays: [[Int]]? = nil,
        forecastActiveDays: Int? = nil,
        forecastHourly: [Double]? = nil,
        forecastWeekdayHourly: [[Double]]? = nil
    ) {
        self.hourly = hourly
        self.intensity = intensity ?? Array(repeating: 0, count: 24)
        self.hourSampleDays = hourSampleDays
        self.observedDays = observedDays
        self.weekdayHourly = weekdayHourly ?? Self.emptyGrid(0.0)
        self.weekdaySampleDays = weekdaySampleDays ?? Self.emptyGrid(0)
        self.forecastActiveDays = forecastActiveDays ?? observedDays
        self.forecastHourly = forecastHourly ?? Array(repeating: 0, count: 24)
        self.forecastWeekdayHourly = forecastWeekdayHourly ?? Array(repeating: self.forecastHourly, count: 7)
    }

    /// En aktif saat. Eşitlikte tüketimi büyük olan saat kazanır; o da
    /// eşitse erken saat.
    public var peakHour: Int? {
        guard let maximum = hourly.max(), maximum > 0 else { return nil }
        return (0..<24)
            .filter { hourly[$0] == maximum }
            .max { intensity[$0] < intensity[$1] || (intensity[$0] == intensity[$1] && $0 > $1) }
    }

    /// Profil güvenilir sayılacak kadar gözlem var mı.
    ///
    /// Üç günün altında saatlik desen gürültüden ibaret oluyor.
    public var isReliable: Bool { observedDays >= Self.minimumDays }

    public static let minimumDays = 3

    public static let empty = UsageProfile(
        hourly: Array(repeating: 0, count: 24),
        hourSampleDays: Array(repeating: 0, count: 24),
        observedDays: 0
    )

    // MARK: - Ayarlar

    /// İki örnek arası bundan uzunsa aralık atlanır: uygulama kapalıydı ya da
    /// Mac uyuyordu; artışın aralığın neresinde olduğu bilinemez.
    static let maxGap: TimeInterval = 3600
    /// Yakın günler ağır basıyor: alışkanlık kayıyor, iki ay önceki düzen
    /// dünküyle eşit sayılmamalı. Yarı ömür 21 gün.
    static let halfLifeDays: Double = 21
    /// Payın paydası en az bu kadar (ağırlıklı) gün. Tek bir gece görülen
    /// bir saat 1/1 = %100 pay almasın: bir kez görülen saat en fazla 1/3.
    static let minimumHourDays: Double = 3
    /// Hafta günü hücreleri yedide bir veriyle çalışıyor; eşik daha düşük.
    static let minimumCellDays: Double = 2

    // MARK: - İnşa

    /// Kota örneklerinden profil çıkarır.
    ///
    /// - Parameters:
    ///   - samples: Zamana göre artan sıralı örnekler.
    ///   - utcOffsets: Varsa her örneğin KAYDEDİLDİĞİ andaki yerel saat farkı
    ///     (saniye). Saat ve gün buradan okunur; böylece başka bir saat
    ///     dilimine geçmek geçmişin tamamını kaydırmıyor. Yoksa `calendar`.
    ///   - now: Yakınlık ağırlığının referansı. Varsayılan en yeni örnek.
    public static func build(
        from samples: [QuotaSample],
        utcOffsets: [Int?] = [],
        calendar: Calendar = .current,
        now: Date? = nil
    ) -> UsageProfile {
        guard samples.count > 1 else { return .empty }
        let reference = now ?? samples[samples.count - 1].date

        func offset(_ index: Int) -> Int {
            if index < utcOffsets.count, let value = utcOffsets[index] { return value }
            return calendar.timeZone.secondsFromGMT(for: samples[index].date)
        }

        var collector = Collector(reference: reference)

        // Her org KENDİ zincirinde: iki ayrı 5 saatlik pencere arasındaki
        // fark tüketim değil. Aynı hesabın iki kaynağı (Desktop dosyası ve
        // sunucu okuması) farklı etiketle gelebiliyor; o yüzden fark çiftleri
        // atılmıyor, her seri kendi içinde okunup aşağıda birleştiriliyor.
        var previousByOrg: [String: Int] = [:]
        var highWater: [String: (five: Int, seven: Int)] = [:]
        for index in samples.indices {
            let current = samples[index]
            defer { previousByOrg[current.org] = index }
            guard let previousIndex = previousByOrg[current.org] else {
                highWater[current.org] = (current.fiveHour, current.sevenDay)
                continue
            }
            let previous = samples[previousIndex]
            let gap = current.date.timeIntervalSince(previous.date)
            // Saat farkı değişen aralığın hangi yerel saate ait olduğu belirsiz.
            guard gap > 0, gap <= maxGap, offset(previousIndex) == offset(index) else {
                highWater[current.org] = (current.fiveHour, current.sevenDay)
                continue
            }
            let peak = highWater[current.org] ?? (previous.fiveHour, previous.sevenDay)
            let fiveReset = ResetRule.didReset(previous: peak.five, current: current.fiveHour,
                                               gap: gap, duration: WindowKind.fiveHour.duration)
            let sevenReset = ResetRule.didReset(previous: peak.seven, current: current.sevenDay,
                                                gap: gap, duration: WindowKind.sevenDay.duration)
            let fiveDelta = fiveReset ? 0 : max(0, current.fiveHour - peak.five)
            let sevenDelta = sevenReset ? 0 : max(0, current.sevenDay - peak.seven)
            highWater[current.org] = (fiveReset ? current.fiveHour : max(peak.five, current.fiveHour),
                                     sevenReset ? current.sevenDay : max(peak.seven, current.sevenDay))
            // 40→39→40 gibi gecikmiş okumalar tekrar tekrar tüketim üretmesin.
            // Sıfırlanmanın iki yanındaki fark bilinemez; hareketsizlik de değildir.
            guard !fiveReset || sevenDelta > 0 else { continue }
            collector.add(
                from: previous.date, to: current.date, offset: offset(previousIndex),
                delta: Double(fiveDelta), weeklyDelta: Double(sevenDelta), org: current.org
            )
        }
        return collector.profile()
    }

    static func emptyGrid<T>(_ value: T) -> [[T]] {
        Array(repeating: Array(repeating: value, count: 24), count: 7)
    }
}

// MARK: - Toplama

private struct Collector {
    /// Yerel gün (1970'ten beri gün sayısı) + saat.
    struct Slot: Hashable {
        let day: Int
        let hour: Int
    }

    let reference: Date
    /// Gözlenen (gün, saat) çiftleri ve günlerin ağırlığı / hafta günü.
    private var covered: Set<Slot> = []
    private var dayWeight: [Int: Double] = [:]
    private var dayWeekday: [Int: Int] = [:]
    /// Org başına (gün, saat) tüketimi. Birleştirmede org'lar arası en
    /// büyüğü alınıyor: aynı hesabın iki kaynağı aynı tüketimi iki kez
    /// görüyor, toplamak onu ikiye katlardı.
    private var consumption: [String: [Slot: Double]] = [:]
    /// Tüketim olan (gün, saat) çiftleri.
    private var active: Set<Slot> = []
    private var weeklyConsumption: [String: [Slot: Double]] = [:]
    private var intensityActive: Set<Slot> = []

    init(reference: Date) {
        self.reference = reference
    }

    mutating func add(from start: Date, to end: Date, offset: Int, delta: Double, weeklyDelta: Double, org: String) {
        let shift = TimeInterval(offset)

        // Kapsam: aralığın değdiği HER yerel saat gözlenmiştir; tüketim
        // olmasa da o saatin paydasına girer.
        var cursor = start
        while cursor < end {
            let local = cursor.timeIntervalSince1970 + shift
            let nextBoundary = (local / 3600).rounded(.down) * 3600 + 3600
            covered.insert(register(cursor, shift: shift))
            cursor = min(end, Date(timeIntervalSince1970: nextBoundary - shift))
        }

        // Tüketim tek saate yazılıyor: aralığın ORTA noktasının saati.
        // Eskiden bitiş örneğinin saatine yazılıyordu ve 13:55-14:00
        // arasındaki iş 14:00'e gidiyordu. Saat sınırında orantılı bölmek de
        // komşu saate kırıntı bırakıp onu "aktif" sayardı; pay bir evet/hayır.
        guard delta > 0 || weeklyDelta > 0 else { return }
        let middle = register(start.addingTimeInterval(end.timeIntervalSince(start) / 2), shift: shift)
        active.insert(middle)
        if delta > 0 {
            intensityActive.insert(middle)
            consumption[org, default: [:]][middle, default: 0] += delta
        }
        weeklyConsumption[org, default: [:]][middle, default: 0] += weeklyDelta
    }

    /// Anın yerel (gün, saat) anahtarı; günü ilk kez görüyorsa ağırlığını
    /// ve hafta gününü kaydeder.
    ///
    /// Takvim yok, aritmetik: saat farkı uygulanmış epoch saniyesi UTC gibi
    /// okunuyor ve UTC'de yaz saati yok. 60 günlük arşivde on binlerce
    /// aralık var; her biri için `Calendar` çağırmak ana iş parçacığında
    /// ölçülür bir maliyetti.
    private mutating func register(_ date: Date, shift: TimeInterval) -> Slot {
        let local = date.timeIntervalSince1970 + shift
        let day = Int((local / 86_400).rounded(.down))
        let hour = Int(((local - Double(day) * 86_400) / 3600).rounded(.down))
        if dayWeight[day] == nil {
            let age = max(0, reference.timeIntervalSince(date)) / 86_400
            dayWeight[day] = pow(0.5, age / UsageProfile.halfLifeDays)
            // 1 Ocak 1970 Perşembe; satır 0 Pazartesi.
            dayWeekday[day] = ((day + 3) % 7 + 7) % 7
        }
        return Slot(day: day, hour: min(max(hour, 0), 23))
    }

    func profile() -> UsageProfile {
        guard !covered.isEmpty else { return .empty }

        var merged: [Slot: Double] = [:]
        for perOrg in consumption.values {
            for (slot, value) in perOrg { merged[slot] = max(merged[slot] ?? 0, value) }
        }

        var weeklyMerged: [Slot: Double] = [:]
        for perOrg in weeklyConsumption.values {
            for (slot, value) in perOrg { weeklyMerged[slot] = max(weeklyMerged[slot] ?? 0, value) }
        }
        var weeklySpent = [Double](repeating: 0, count: 24)
        var weekdaySpent = UsageProfile.emptyGrid(0.0)
        var weekdayWeight = [Double](repeating: 0, count: 7)
        var weekdayDays = [Int](repeating: 0, count: 7)
        for (day, weight) in dayWeight {
            let weekday = dayWeekday[day] ?? 0
            weekdayWeight[weekday] += weight
            weekdayDays[weekday] += 1
        }
        for (slot, value) in weeklyMerged {
            let spent = value * (dayWeight[slot.day] ?? 0)
            weeklySpent[slot.hour] += spent
            weekdaySpent[dayWeekday[slot.day] ?? 0][slot.hour] += spent
        }
        let totalWeight = dayWeight.values.reduce(0, +)
        let forecastHourly = weeklySpent.map { $0 / max(totalWeight, 1) }
        let forecastGrid = (0..<7).map { day in
            // Haftanın belli bir gününden en az üç gözlem yoksa genel ritim.
            weekdayDays[day] >= 3
                ? weekdaySpent[day].map { $0 / max(weekdayWeight[day], 1) }
                : forecastHourly
        }

        var intensityWeight = [Double](repeating: 0, count: 24)
        var coveredWeight = [Double](repeating: 0, count: 24)
        var activeWeight = [Double](repeating: 0, count: 24)
        var spentWeighted = [Double](repeating: 0, count: 24)
        var coveredDays = [Int](repeating: 0, count: 24)
        var cellCovered = UsageProfile.emptyGrid(0.0)
        var cellActive = UsageProfile.emptyGrid(0.0)
        var cellDays = UsageProfile.emptyGrid(0)

        for slot in covered {
            let weight = dayWeight[slot.day] ?? 0
            let weekday = dayWeekday[slot.day] ?? 0
            coveredWeight[slot.hour] += weight
            coveredDays[slot.hour] += 1
            cellCovered[weekday][slot.hour] += weight
            cellDays[weekday][slot.hour] += 1
        }
        // Aktif ama kapsanmamış bir anahtar olamaz: orta nokta aralığın
        // içinde ve aralığın her parçası kapsanıyor.
        for slot in active {
            let weight = dayWeight[slot.day] ?? 0
            activeWeight[slot.hour] += weight
            cellActive[dayWeekday[slot.day] ?? 0][slot.hour] += weight
            if intensityActive.contains(slot) {
                intensityWeight[slot.hour] += weight
                spentWeighted[slot.hour] += weight * (merged[slot] ?? 0)
            }
        }

        let hourly = (0..<24).map {
            activeWeight[$0] / max(coveredWeight[$0], UsageProfile.minimumHourDays)
        }
        let intensity = (0..<24).map {
            intensityWeight[$0] > 0 ? spentWeighted[$0] / intensityWeight[$0] : 0
        }
        let grid = (0..<7).map { weekday in
            (0..<24).map { hour in
                cellActive[weekday][hour] / max(cellCovered[weekday][hour], UsageProfile.minimumCellDays)
            }
        }

        return UsageProfile(
            hourly: hourly,
            intensity: intensity,
            hourSampleDays: coveredDays,
            observedDays: Set(covered.map(\.day)).count,
            weekdayHourly: grid,
            weekdaySampleDays: cellDays,
            forecastActiveDays: Set(weeklyMerged.filter { $0.value > 0 }.map { $0.key.day }).count,
            forecastHourly: forecastHourly, forecastWeekdayHourly: forecastGrid
        )
    }
}
