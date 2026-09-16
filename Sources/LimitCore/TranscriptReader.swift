import Foundation

/// Bir asistan yanıtının kullanım kaydı.
public struct ActivityEvent: Sendable, Equatable {
    public let date: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    /// Pencere tüketimiyle ilişkilendirilen toplam. Cache okuma da limite sayılır.
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

/// Saatlik aktivite dağılımı ve model kırılımı.
public struct ActivitySummary: Sendable {
    /// 0-23 arası her saat için toplam token. Yerel saat dilimine göre.
    public let hourlyTokens: [Int]
    public let modelTokens: [String: Int]
    public let eventCount: Int
    public let firstEvent: Date?
    public let lastEvent: Date?
    /// Son günlerin olayları, model payını bir pencereye göre hesaplayabilmek için.
    ///
    /// Tüm arşiv üzerinden hesaplanan pay yanıltıcı: aylar önce yoğun kullanılan
    /// bir model, bu haftaki kotada hiç yeri olmasa bile payda görünüyor.
    public let recentEvents: [ActivityEvent]

    /// Verilen model ailesinin toplam token içindeki payı, 0-1.
    public func share(matching prefix: String) -> Double {
        Self.share(of: modelTokens, matching: prefix)
    }

    /// Aynı pay, ama yalnızca verilen andan sonraki kullanım üzerinden.
    public func share(matching prefix: String, since: Date) -> Double? {
        // Pencere elimizdeki geçmişten daha geriye gidiyorsa hesaplanamaz.
        guard let oldest = recentEvents.first?.date, oldest <= since else { return nil }

        var tokens: [String: Int] = [:]
        for event in recentEvents where event.date >= since {
            tokens[event.model, default: 0] += event.totalTokens
        }
        return Self.share(of: tokens, matching: prefix)
    }

    private static func share(of tokens: [String: Int], matching prefix: String) -> Double {
        let total = tokens.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let matched = tokens.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +)
        return Double(matched) / Double(total)
    }
}

/// Paralel tarama sonuçlarının kilit altında biriktiği kap.
///
/// `concurrentPerform` içinden doğrudan bir `var` diziye yazmak, kilit kullanılsa
/// bile Swift 6 eşzamanlılık denetiminden geçmez. Durumu bir sınıfın içine alıp
/// erişimi tek bir kilide bağlamak hem doğru hem de derleyiciye kanıtlanabilir.
private final class ResultSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(key: String, event: ActivityEvent)] = []

    init() { storage.reserveCapacity(64 << 10) }

    func append(_ items: [(key: String, event: ActivityEvent)]) {
        guard !items.isEmpty else { return }
        lock.lock()
        storage.append(contentsOf: items)
        lock.unlock()
    }

    func drain() -> [(key: String, event: ActivityEvent)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// `~/.claude/projects/**/*.jsonl` transcript dosyalarını okur.
///
/// Bu katman kota yüzdesi vermez, veremez: claude.ai sohbetleri ve Cowork kullanımı
/// aynı pencereyi tüketir ama bu dosyalara hiç yazılmaz. Yalnızca aktivite
/// dağılımı ve model kırılımı için kullanılır.
public struct TranscriptReader: Sendable {
    public static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    public let root: URL
    /// Bu tarihten eski olaylar atlanır. Tam tarama yerine artımlı okuma için.
    public let since: Date?

    public init(root: URL = TranscriptReader.defaultRoot, since: Date? = nil) {
        self.root = root
        self.since = since
    }

    public func summarize(calendar: Calendar = .current) -> ActivitySummary {
        let files = transcriptFiles()

        // Dosyalar birbirinden bağımsız okunabiliyor ve iş disk okuma ile JSON
        // ayrıştırmadan ibaret. Tek çekirdekte 1,8 GB'lık arşiv saniyeler sürüyor,
        // çekirdeklere dağıtıldığında saniyenin altına iniyor.
        let sink = ResultSink()
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            var local: [(key: String, event: ActivityEvent)] = []
            forEachUsageLine(in: files[index]) { event, key in
                if let since, event.date < since { return }
                local.append((key, event))
            }
            sink.append(local)
        }
        let collected = sink.drain()

        // Aynı istek birden fazla dosyada görünebildiği için tekilleştirme
        // dosya bazında değil, tüm sonuçlar toplandıktan sonra yapılmalı.
        var hourly = [Int](repeating: 0, count: 24)
        var models: [String: Int] = [:]
        var seen = Set<String>()
        seen.reserveCapacity(collected.count)
        var count = 0
        var first: Date?
        var last: Date?
        var recent: [ActivityEvent] = []

        // Haftalık pencere en fazla 7 gün; 10 gün pay hesabı için fazlasıyla
        // yeterli ve tüm arşivi bellekte tutmaktan kaçınıyor.
        let recentCutoff = Date().addingTimeInterval(-10 * 24 * 3600)

        for (key, event) in collected {
            guard seen.insert(key).inserted else { continue }
            count += 1
            hourly[calendar.component(.hour, from: event.date)] += event.totalTokens
            models[event.model, default: 0] += event.totalTokens
            if first == nil || event.date < first! { first = event.date }
            if last == nil || event.date > last! { last = event.date }
            if event.date >= recentCutoff { recent.append(event) }
        }

        return ActivitySummary(
            hourlyTokens: hourly,
            modelTokens: models,
            eventCount: count,
            firstEvent: first,
            lastEvent: last,
            recentEvents: recent.sorted { $0.date < $1.date }
        )
    }

    func transcriptFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    /// Satır satır okur ve yalnızca kullanım içeren asistan satırlarını ayrıştırır.
    ///
    /// 1,8 GB'lık bir arşivde her satırı JSON olarak ayrıştırmak israf olur;
    /// önce ucuz bir alt dizi taraması yapılır, JSON yalnızca eşleşen satırlara uygulanır.
    private func forEachUsageLine(in file: URL, _ body: (ActivityEvent, String) -> Void) {
        guard let reader = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? reader.close() }

        let newline = UInt8(ascii: "\n")
        var carry: [UInt8] = []

        // `Data.SubSequence` üzerinde bayt bayt gezmek ölçülebilir biçimde yavaş:
        // her erişim indeks aritmetiğine giriyor. Parça başına tek kopya alıp
        // düz bir bayt dizisi üzerinde çalışmak aynı işi kat kat hızlandırıyor.
        while let chunk = try? reader.read(upToCount: 8 << 20), !chunk.isEmpty {
            var buffer = carry
            buffer.append(contentsOf: chunk)
            var start = 0
            var i = 0
            while i < buffer.count {
                if buffer[i] == newline {
                    parse(bytes: buffer, range: start..<i, body)
                    start = i + 1
                }
                i += 1
            }
            carry = start < buffer.count ? Array(buffer[start...]) : []
        }
        if !carry.isEmpty { parse(bytes: carry, range: 0..<carry.count, body) }
    }

    private func parse(bytes: [UInt8], range: Range<Int>, _ body: (ActivityEvent, String) -> Void) {
        guard range.count > 64, contains(bytes, range, Self.usageMarker) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: Data(bytes[range])) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let date = Self.parseDate(stamp)
        else { return }

        let event = ActivityEvent(
            date: date,
            model: message["model"] as? String ?? "unknown",
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
        )
        // Aynı istek birden fazla dosyada görünebilir (özet, dallanma, yeniden oynatma).
        let key = (object["requestId"] as? String) ?? (message["id"] as? String) ?? stamp
        body(event, key)
    }

    private static let usageMarker = Array(#""usage""#.utf8)

    /// Düz bayt dizisi üzerinde alt dizi araması, kopya çıkarmadan.
    private func contains(_ haystack: [UInt8], _ range: Range<Int>, _ needle: [UInt8]) -> Bool {
        let n = needle.count
        guard range.count >= n else { return false }
        let first = needle[0]
        var i = range.lowerBound
        let limit = range.upperBound - n
        while i <= limit {
            if haystack[i] == first {
                var j = 1
                while j < n, haystack[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    /// `2026-08-21T08:47:59.954Z` biçimini elle ayrıştırır.
    ///
    /// `ISO8601DateFormatter` hem Swift 6 altında Sendable değil hem de 42 binden
    /// fazla damga için gereksiz yavaş. Biçim sabit olduğu için doğrudan okumak
    /// daha hızlı ve eşzamanlılık açısından güvenli.
    static func parseDate(_ s: String) -> Date? {
        let b = Array(s.utf8)
        guard b.count >= 19, b[4] == UInt8(ascii: "-"), b[10] == UInt8(ascii: "T") else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for i in range {
                let digit = Int(b[i]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19)
        else { return nil }

        var fraction = 0.0
        if b.count > 20, b[19] == UInt8(ascii: ".") {
            var i = 20
            var scale = 0.1
            while i < b.count, (48...57).contains(b[i]) {
                fraction += Double(Int(b[i]) - 48) * scale
                scale /= 10
                i += 1
            }
        }

        // Damgalar UTC ("Z"). Takvim dönüşümü yerine doğrudan gün sayısı hesabı.
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// Howard Hinnant'ın civil_from_days algoritmasının tersi. 1970-01-01'den gün farkı.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
