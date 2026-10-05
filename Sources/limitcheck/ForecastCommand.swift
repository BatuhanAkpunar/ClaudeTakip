import Foundation
import LimitCore

// Haftalık tahmin tanılaması.
enum ForecastCommand {
    static func run(deriver: WindowDeriver, projector: Projector) -> Never {
        print("\nHAFTALIK TAHMİN (takvim ortalaması + saatlik kullanım deseni)")
        // Arşiv yoksa açılmıyor: açmak dosyayı oluşturur.
        let store = FileManager.default.fileExists(atPath: HistoryStore.defaultURL.path)
            ? (try? HistoryStore()) : nil
        let cutoff = Date(timeIntervalSince1970: 0)
        let allSamples: [QuotaSample] = store.flatMap { try? $0.samples(since: cutoff) } ?? []
        let now = Date()
        let profile = QuotaArchive(history: store).profile(now: now)
        let five = deriver.derive(.fiveHour, from: allSamples, now: now)
        let blockedUntil = (five?.utilization ?? 0) >= 100 ? five?.resetAt : nil
        if let state = deriver.derive(.sevenDay, from: allSamples), let p = projector.project(state, now: now, profile: profile, blockedUntil: blockedUntil),
           let start = state.windowStart, let reset = state.resetAt {
            let elapsed = Date().timeIntervalSince(start) / 3600
            let total = reset.timeIntervalSince(start) / 3600
            print("  kullanım        %\(state.utilization)")
            print("  geçen / toplam  \(String(format: "%.1f", elapsed)) / \(String(format: "%.0f", total)) saat")
            if let m = p.multiplier {
                print("  pace            \(String(format: "%.2f", m))×  (tahmini toplam ÷ 100)")
            }
            print("  saatlik desen    \(p.usesActivityPattern ? "EVET" : "hayır; takvim ortalaması")")
            print("  pencere sonunda  %\(Int(p.projectedUtilization.rounded()))")
            if let f = p.fillAt {
                print("  %100'e ulaşma    \(fmt(f))")
            } else {
                print("  %100'e ulaşma    pencere içinde ulaşmıyor")
            }
            print("  aşım var mı      \(p.willOverrun ? "EVET" : "hayır")")
        } else {
            print("  tahmin üretilemedi")
        }
        print(String(repeating: "─", count: 62))
        exit(0)
    }
}
