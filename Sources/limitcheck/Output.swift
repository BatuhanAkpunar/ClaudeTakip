import Foundation

/// Çıktı tarihleri için tek biçimlendirici. Biçimlendiriciler komut satırı
/// aracı tek iş parçacığında çalıştığı için paylaşılıyor.
nonisolated(unsafe) let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd MMM HH:mm"
    f.locale = Locale(identifier: "tr_TR")
    return f
}()

nonisolated(unsafe) let isoFormatter = ISO8601DateFormatter()

func fmt(_ date: Date?) -> String {
    guard let date else { return "-" }
    return shortDateFormatter.string(from: date)
}

func duration(_ interval: TimeInterval?) -> String {
    guard let interval, interval > 0 else { return "-" }
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    return h > 0 ? "\(h)sa \(m)dk" : "\(m)dk"
}

func bar(_ percent: Int, width: Int = 24) -> String {
    let filled = max(0, min(width, percent * width / 100))
    return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
}
