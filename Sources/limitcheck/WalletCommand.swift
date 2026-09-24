import Foundation
import LimitCore

/// `limitcheck wallet`: yalnızca sunucu cüzdan alanlarını doğrular, ağır yerel
/// taramayı hiç çalıştırmaz. Oturum anahtarını ASLA basmaz.
enum WalletCommand {
    static func run() -> Never {
        print("SUNUCU CÜZDAN DOĞRULAMASI")
        // `swift run` Debug derliyor ve varsayılan yol session-debug.json;
        // kurulu uygulamayı tanılamak için varsayılan YAYIN oturumu.
        // Geliştirme oturumu yalnızca açıkça istenirse.
        let sessionURL = CommandLine.arguments.contains("--debug-session")
            ? SessionStore.defaultURL : SessionStore.releaseURL
        guard let session = SessionStore(url: sessionURL).load() else {
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
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let root {
                    print("  --- TÜM PENCERELER (ham) ---")
                    for key in root.keys.sorted() {
                        guard let obj = root[key] as? [String: Any] else { continue }
                        let util = obj["utilization"] ?? obj["used_percentage"] ?? "-"
                        let reset = obj["resets_at"] ?? "-"
                        print("    \(key.padding(toLength: 24, withPad: " ", startingAt: 0)) util=\(util)  reset=\(reset)")
                    }
                    print("  ----------------------------")
                }
                if let root {
                    if let extra = root["extra_usage"] as? [String: Any] {
                        print("  extra_usage ham alanlar:")
                        for k in extra.keys.sorted() { print("    \(k) = \(extra[k] ?? "nil")") }
                    } else {
                        print("  extra_usage: YOK. kök anahtarlar: \(root.keys.sorted().joined(separator: ", "))")
                    }
                }
                // Aynı gövde yeniden ayrıştırılıyor: `usage` ikinci, birebir
                // aynı bir istek atıyordu.
                let parsed = ServerUsage(json: root ?? [:])
                print("  model pencereleri (\(parsed.modelWindows.count)):")
                for (name, w) in parsed.modelWindows.sorted(by: { $0.key < $1.key }) {
                    print("    \(name): util=\(w.utilization) reset=\(w.resetsAt.map { isoFormatter.string(from: $0) } ?? "nil")")
                }
                if let root {
                    print("  usage kök anahtarlar: \(root.keys.sorted().joined(separator: ", "))")
                    if let limits = root["limits"] as? [[String: Any]] {
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
}
