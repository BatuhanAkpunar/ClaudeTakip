import Foundation
import LimitCore

// ── Yenileme boru hattının maliyeti ───────────────────────────────────────────
// Her 30 saniyede bir çalışan iş: arşiv okuma + profil inşası + tahmin.
enum PerfCommand {
    static func run() -> Never {
        print("\nYENİLEME MALİYETİ")
        // Arşiv yoksa AÇILMIYOR: `HistoryStore()` dosyayı oluşturur ve tanılama
        // aracı canlı uygulamanın arşivini yaratmış olurdu.
        guard FileManager.default.fileExists(atPath: HistoryStore.defaultURL.path),
              let store = try? HistoryStore() else { print("  arşiv yok"); exit(0) }
        func timed(_ label: String, _ body: () -> Void) {
            var best = Double.infinity
            for _ in 0..<5 { let t = Date(); body(); best = min(best, Date().timeIntervalSince(t) * 1000) }
            print("  \(label.padding(toLength: 38, withPad: " ", startingAt: 0)) \(String(format: "%7.1f", best)) ms")
        }
        let longCutoff = Date().addingTimeInterval(-60 * 24 * 3600)
        let shortCutoff = Date().addingTimeInterval(-9 * 24 * 3600)
        let long = (try? store.samples(since: longCutoff)) ?? []
        let short = (try? store.samples(since: shortCutoff)) ?? []
        print("  örnek: 60 gün=\(long.count)  9 gün=\(short.count)")
        timed("SQLite okuma (60 gün)") { _ = try? store.samples(since: longCutoff) }
        timed("SQLite okuma (9 gün)") { _ = try? store.samples(since: shortCutoff) }
        timed("UsageProfile.build (60 gün)") { _ = UsageProfile.build(from: long) }
        let d = WindowDeriver(); let pr = Projector()
        // İki etiket iki AYRI dilimden türetiliyor; önceden aynı durum iki
        // kez ölçülüyordu.
        if let st = d.derive(.sevenDay, from: long) {
            timed("projeksiyon (60 günlük dilim)") { _ = pr.project(st) }
        }
        if let st = d.derive(.sevenDay, from: short) {
            timed("projeksiyon (9 günlük dilim)") { _ = pr.project(st) }
        }
        print(String(repeating: "─", count: 62))
        exit(0)
    }
}
