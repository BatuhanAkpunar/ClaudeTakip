import Foundation
import LimitCore

// ── Haftalık tahmin doğrulaması (kullanıcının formülü) ──────────────────────
enum ForecastCommand {
    static func run(deriver: WindowDeriver, projector: Projector) -> Never {
        print("\nHAFTALIK TAHMİN (ideal kullanım = geçen ÷ toplam × 100)")
        // Arşiv yoksa açılmıyor: açmak dosyayı oluşturur.
        let store = FileManager.default.fileExists(atPath: HistoryStore.defaultURL.path)
            ? (try? HistoryStore()) : nil
        let cutoff = Date(timeIntervalSince1970: 0)
        let allSamples: [QuotaSample] = store.flatMap { try? $0.samples(since: cutoff) } ?? []
        if let state = deriver.derive(.sevenDay, from: allSamples), let p = projector.project(state),
           let start = state.windowStart, let reset = state.resetAt {
            let elapsed = Date().timeIntervalSince(start) / 3600
            let total = reset.timeIntervalSince(start) / 3600
            let ideal = elapsed / total * 100
            print("  kullanım        %\(state.utilization)")
            print("  geçen / toplam  \(String(format: "%.1f", elapsed)) / \(String(format: "%.0f", total)) saat")
            print("  ideal kullanım  %\(String(format: "%.2f", ideal))")
            if let m = p.multiplier {
                print("  pace            \(String(format: "%.2f", m))×  (= %\(state.utilization) ÷ %\(String(format: "%.2f", ideal)))")
            }
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
