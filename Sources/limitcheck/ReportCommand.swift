import Foundation
import LimitCore

/// Varsayılan rapor: Katman A kota yüzdeleri, pencere türetme ve projeksiyon,
/// Katman B aktivite dağılımı ve Fable tahmini.
enum ReportCommand {
    static func run(deriver: WindowDeriver, projector: Projector) {
        let now = Date()
        print("Claude Takip | veri çekirdeği doğrulaması")
        print(String(repeating: "─", count: 62))

        // ── Katman A: gerçek kota yüzdeleri ───────────────────────────────────────────
        let reader = PlanUsageReader()
        let samples: [QuotaSample]
        do {
            let t0 = Date()
            samples = try reader.read()
            let ms = Date().timeIntervalSince(t0) * 1000
            print("\nKATMAN A  \(reader.url.lastPathComponent)")
            print("  örnek        \(samples.count) adet, \(String(format: "%.0f", ms)) ms'de okundu")
            if let first = samples.first, let last = samples.last {
                let days = last.date.timeIntervalSince(first.date) / 86400
                print("  kapsam       \(fmt(first.date)) → \(fmt(last.date))  (\(String(format: "%.1f", days)) gün)")
            }
            if let modified = reader.lastModified() {
                let freshness = Freshness(lastUpdate: modified, now: now)
                let label = switch freshness {
                case .live: "canlı"
                case .aging: "yaşlanıyor"
                case .stale: "eski"
                }
                print("  tazelik      \(label), son yazım \(duration(now.timeIntervalSince(modified))) önce")
            }
        } catch {
            print("  HATA: \(error)")
            exit(1)
        }

        // ── Pencere türetme ve projeksiyon ────────────────────────────────────────────
        for kind in WindowKind.allCases {
            guard let state = deriver.derive(kind, from: samples, now: now) else { continue }
            let title = kind == .fiveHour ? "5 SAATLİK PENCERE" : "HAFTALIK PENCERE"
            print("\n\(title)")
            print("  kullanım     \(bar(state.utilization)) %\(state.utilization)")
            if state.isIdle {
                print("  durum        pencere henüz başlamadı")
            } else {
                print("  başlangıç    \(fmt(state.windowStart))  (±\(Int(state.startUncertainty / 60)) dk)")
                print("  sıfırlanma   \(fmt(state.resetAt))  →  \(duration(state.timeRemaining(now: now))) sonra")
            }
            let recent = state.observedResets.prefix(4).map { fmt($0) }.joined(separator: ", ")
            print("  gözlenen     \(state.observedResets.count) sıfırlanma [\(recent)]")

            if let p = projector.project(state, now: now) {
                print("  hız          %\(String(format: "%.1f", p.ratePerHour))/saat", terminator: "")
                if let m = p.multiplier { print("  (bu gidişle sıfırlanmada kotanın \(String(format: "%.2f", m))× katı)") } else { print("") }
                print("  projeksiyon  pencere sonunda %\(String(format: "%.0f", p.projectedUtilization))")
                if let fillAt = p.fillAt {
                    let label = p.willOverrun ? "UYARI       " : "dolma anı   "
                    let suffix = p.willOverrun ? "(sıfırlanmadan önce)" : "(sıfırlanmadan sonra, limite çarpılmıyor)"
                    print("  \(label) bu hızla %100'e \(fmt(fillAt)) civarında ulaşılır \(suffix)")
                }
            }
        }

        // ── Katman B: aktivite dağılımı ───────────────────────────────────────────────
        print("\nKATMAN B  ~/.claude/projects")
        let t1 = Date()
        let activity = TranscriptReader().summarize()
        let scanMs = Date().timeIntervalSince(t1) * 1000
        print("  olay         \(activity.eventCount) benzersiz istek, \(String(format: "%.0f", scanMs)) ms'de tarandı")
        if let f = activity.firstEvent, let l = activity.lastEvent {
            print("  kapsam       \(fmt(f)) → \(fmt(l))")
        }

        let peak = activity.hourlyTokens.max() ?? 1
        print("  en aktif saatler (yerel):")
        for hour in 0..<24 {
            let value = activity.hourlyTokens[hour]
            let height = peak > 0 ? value * 30 / peak : 0
            let label = String(format: "%02d", hour)
            print("    \(label)  \(String(repeating: "▇", count: height))")
        }

        let topModels = activity.modelTokens.sorted { $0.value > $1.value }.prefix(5)
        print("  model dağılımı:")
        let totalTokens = activity.modelTokens.values.reduce(0, +)
        for (model, tokens) in topModels {
            let pct = totalTokens > 0 ? Double(tokens) * 100 / Double(totalTokens) : 0
            print("    \(model.padding(toLength: 28, withPad: " ", startingAt: 0)) %\(String(format: "%.1f", pct))")
        }

        // ── Fable tahmini ─────────────────────────────────────────────────────────────
        // Uygulamayla aynı hesap: pay MEVCUT haftalık pencere içinden. Tüm
        // arşivin payı aylar önceki kullanımı bu haftaya yansıtıyordu.
        if let weekly = deriver.derive(.sevenDay, from: samples, now: now) {
            print("\nFABLE (tahmini)")
            if let start = weekly.windowStart,
               let fableShare = activity.share(matching: "claude-fable", since: start) {
                let estimate = fableShare * Double(weekly.utilization)
                print("  token payı   %\(String(format: "%.1f", fableShare * 100)) (bu haftalık pencerede)")
                print("  haftalık     %\(String(format: "%.1f", estimate)) tahmini tüketim")
            } else {
                print("  token payı   hesaplanamadı: pencere başı bilinmiyor ya da yerel geçmiş yetmiyor")
            }
            print("  not          gerçek değer sunucuda (limits → weekly_scoped); `limitcheck wallet` gösterir")
        }

        print("\n" + String(repeating: "─", count: 62))
    }
}
