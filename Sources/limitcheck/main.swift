import Foundation
import LimitCore

// Tamponu kapat: çıktı dosyaya yönlendirildiğinde satırlar anında görünsün.
setvbuf(stdout, nil, _IONBF, 0)

// `limitcheck wallet`: yalnızca sunucu cüzdan alanlarını doğrular, ağır yerel
// taramayı hiç çalıştırmaz. Oturum anahtarını ASLA basmaz.
if CommandLine.arguments.contains("wallet") {
    print("SUNUCU CÜZDAN DOĞRULAMASI")
    guard let session = SessionStore().load() else {
        print("  giriş yok: önce uygulamadan giriş yapın"); exit(0)
    }
    let client = ClaudeWebClient(sessionKey: session.sessionKey)
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        defer { sem.signal() }
        do {
            let org: String
            if let o = session.organizationID { org = o } else { org = try await client.organizationID() }
            print("  org          \(org.prefix(4))…\(org.suffix(2))")
            let data = try await client.rawUsage(organizationID: org)
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("  --- TÜM PENCERELER (ham) ---")
                for key in root.keys.sorted() {
                    guard let obj = root[key] as? [String: Any] else { continue }
                    let util = obj["utilization"] ?? obj["used_percentage"] ?? "-"
                    let reset = obj["resets_at"] ?? "-"
                    print("    \(key.padding(toLength: 24, withPad: " ", startingAt: 0)) util=\(util)  reset=\(reset)")
                }
                print("  ----------------------------")
            }
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let extra = root["extra_usage"] as? [String: Any] {
                    print("  extra_usage ham alanlar:")
                    for k in extra.keys.sorted() { print("    \(k) = \(extra[k] ?? "nil")") }
                } else {
                    print("  extra_usage: YOK. kök anahtarlar: \(root.keys.sorted().joined(separator: ", "))")
                }
            }
            let parsed = try await client.usage(organizationID: org)
            print("  model pencereleri (\(parsed.modelWindows.count)):")
            for (name, w) in parsed.modelWindows.sorted(by: { $0.key < $1.key }) {
                print("    \(name): util=\(w.utilization) reset=\(w.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")
            }
            if let root2 = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("  usage kök anahtarlar: \(root2.keys.sorted().joined(separator: ", "))")
                if let limits = root2["limits"] as? [[String: Any]] {
                    print("  --- LIMITS dizisi (\(limits.count) kayıt) ---")
                    for item in limits {
                        let parts = item.keys.sorted().map { "\($0)=\(item[$0] ?? "nil")" }
                        print("    • \(parts.joined(separator: "  "))")
                    }
                }
            }
            if let w = parsed.wallet {
                print("  ayrıştırılmış: enabled=\(w.isEnabled) limit=\(w.monthlyLimit.map{String($0)} ?? "nil") spent=\(w.usedCredits.map{String($0)} ?? "nil") util=\(w.utilization.map{String($0)} ?? "nil")")
            } else { print("  ayrıştırılmış cüzdan: nil") }
            if let b = await client.balance(organizationID: org) {
                print("  prepaid: remaining=\(b.remaining.map{String($0)} ?? "nil") autoReload=\(b.autoReloadEnabled)")
            } else { print("  prepaid: yanıt yok") }
        } catch { print("  hata: \(error)") }
    }
    sem.wait()
    exit(0)
}

// Faz 1 doğrulama aracı.
// Amaç: arayüz yazmadan önce türetilen sayıların gerçekten doğru olduğunu kanıtlamak.

func fmt(_ date: Date?) -> String {
    guard let date else { return "-" }
    let f = DateFormatter()
    f.dateFormat = "dd MMM HH:mm"
    f.locale = Locale(identifier: "tr_TR")
    return f.string(from: date)
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

let now = Date()
print("Claude Limit | veri çekirdeği doğrulaması")
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
let deriver = WindowDeriver()
let projector = Projector()

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

    if let p = projector.project(state, samples: samples, now: now) {
        print("  hız          %\(String(format: "%.1f", p.ratePerHour))/saat", terminator: "")
        if let m = p.multiplier { print("  (ortalamanın \(String(format: "%.1f", m))× katı)") } else { print("") }
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
let fableShare = activity.share(matching: "claude-fable")
if let weekly = deriver.derive(.sevenDay, from: samples, now: now) {
    let estimate = fableShare * Double(weekly.utilization)
    print("\nFABLE (tahmini)")
    print("  token payı   %\(String(format: "%.1f", fableShare * 100)) of tüm kullanım")
    print("  haftalık     %\(String(format: "%.1f", estimate)) tahmini tüketim")
    print("  not          gerçek model bazlı kota yalnızca OAuth katmanında var, kapalı")
}

print("\n" + String(repeating: "─", count: 62))


// ── Yenileme boru hattının maliyeti ───────────────────────────────────────────
// Her 30 saniyede bir çalışan iş: arşiv okuma + profil inşası + tahmin.
if CommandLine.arguments.contains("perf") {
    print("\nYENİLEME MALİYETİ")
    guard let store = try? HistoryStore() else { print("  arşiv yok"); exit(0) }
    func timed(_ label: String, _ body: () -> Void) {
        var best = Double.infinity
        for _ in 0..<5 { let t = Date(); body(); best = min(best, Date().timeIntervalSince(t) * 1000) }
        print("  \(label.padding(toLength: 38, withPad: " ", startingAt: 0)) \(String(format: "%7.1f", best)) ms")
    }
    let long = (try? store.samples(since: Date().addingTimeInterval(-60 * 24 * 3600))) ?? []
    let short = (try? store.samples(since: Date().addingTimeInterval(-9 * 24 * 3600))) ?? []
    print("  örnek: 60 gün=\(long.count)  9 gün=\(short.count)")
    timed("SQLite okuma (60 gün)") { _ = try? store.samples(since: Date().addingTimeInterval(-60 * 24 * 3600)) }
    timed("SQLite okuma (9 gün)") { _ = try? store.samples(since: Date().addingTimeInterval(-9 * 24 * 3600)) }
    timed("UsageProfile.build (60 gün)") { _ = UsageProfile.build(from: long) }
    let d = WindowDeriver(); let pr = Projector()
    if let st = d.derive(.sevenDay, from: short) {
        timed("projeksiyon (60 günlük dilim)") { _ = pr.project(st, samples: long) }
        timed("projeksiyon (9 günlük dilim)") { _ = pr.project(st, samples: short) }
    }
    print(String(repeating: "─", count: 62))
    exit(0)
}

// ── Haftalık davranış-temelli tahmin doğrulaması ──────────────────────────────
if CommandLine.arguments.contains("forecast") {
    print("\nHAFTALIK TAHMİN (davranış temelli)")
    let store = try? HistoryStore()
    let allSamples: [QuotaSample] = ((try? store?.samples(since: Date(timeIntervalSince1970: 0))) ?? nil) ?? []
    let deriver = WindowDeriver()
    let projector = Projector()
    if let state = deriver.derive(.sevenDay, from: allSamples), let p = projector.project(state, samples: allSamples) {
        print("  kullanım        %\(state.utilization)")
        print("  geçmişe mi dayalı: \(p.usesHistory ? "EVET (davranış eğrisi)" : "hayır (aktif-saat/doğrusal)")")
        print("  pencere sonunda  %\(Int(p.projectedUtilization.rounded()))")
        if let f = p.fillAt {
            let df = DateFormatter(); df.dateFormat = "dd MMM HH:mm"; df.locale = Locale(identifier: "tr_TR")
            print("  %100'e ulaşma    \(df.string(from: f))")
        } else {
            print("  %100'e ulaşma    pencere içinde ulaşmıyor")
        }
        print("  aşım var mı      \(p.willOverrun ? "EVET" : "hayır")")
        print("  eğri nokta sayısı \(p.forecast.count)")
        // Uygulamanın kullandığı iki dilimi karşılaştır: 9 günlük dilim
        // davranış modelini besleyemez (2 tam hafta gerekir), 60 günlük besler.
        let short = allSamples.filter { $0.date >= Date().addingTimeInterval(-9 * 24 * 3600) }
        let long = allSamples.filter { $0.date >= Date().addingTimeInterval(-60 * 24 * 3600) }
        for (ad, dilim) in [("9 gün (eski uygulama yolu)", short), ("60 gün (yeni uygulama yolu)", long)] {
            if let st = deriver.derive(.sevenDay, from: dilim), let pp = projector.project(st, samples: dilim) {
                print("  \(ad): örnek=\(dilim.count) usesHistory=\(pp.usesHistory) sonu=%\(Int(pp.projectedUtilization.rounded()))")
            }
        }
        if p.forecast.count > 2 {
            let mid = p.forecast[p.forecast.count/2]
            print("  eğri ortası      pos \(String(format: "%.2f", mid.position)) -> %\(Int(mid.utilization.rounded()))")
        }
    } else {
        print("  tahmin üretilemedi")
    }
    print(String(repeating: "─", count: 62))
    exit(0)
}
