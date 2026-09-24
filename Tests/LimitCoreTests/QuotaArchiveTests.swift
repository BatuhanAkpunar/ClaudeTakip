import Testing
import Foundation
@testable import LimitCore

@Suite("Kota arşivi")
struct QuotaArchiveTests {
    private func makeStore() throws -> (HistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudetakip-archive-test-\(UUID().uuidString).sqlite")
        return (try HistoryStore(url: url), url)
    }

    private func sample(_ secondsAgo: TimeInterval, fh: Int, sd: Int = 1) -> QuotaSample {
        QuotaSample(date: Date().addingTimeInterval(-secondsAgo), org: "test",
                    fiveHour: fh, sevenDay: sd, extraUsage: nil)
    }

    @Test("Arşiv yalnızca pencere içindeki taze satır sayısı kadar satırı varsa kazanır")
    func archiveWinsOnlyWithEnoughRows() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        // Arşivde pencere içinde iki eski satır var.
        _ = try store.importSamples([sample(3 * 3600, fh: 1), sample(2 * 3600, fh: 2)])
        let archive = QuotaArchive(history: store)

        // Taze tek satır + pencere dışı bir satır: pencere içinde 1 taze,
        // arşivde 3 (içe aktarılanla) → arşiv kazanır.
        let fresh = [sample(20 * 24 * 3600, fh: 9), sample(60, fh: 3)]
        let merged = archive.merge(fresh: fresh)
        #expect(merged.count == 3)
        #expect(merged.map(\.fiveHour) == [1, 2, 3])
    }

    @Test("Arşivde pencere içinde daha az satır varsa taze veri döner")
    func freshWinsWhenArchiveShort() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = QuotaArchive(history: store)
        // Aynı zaman damgası birincil anahtar: üç taze satırdan ikisi aynı an.
        let t = Date().addingTimeInterval(-60)
        let dup = QuotaSample(date: t, org: "test", fiveHour: 5, sevenDay: 1, extraUsage: nil)
        let dup2 = QuotaSample(date: t, org: "test", fiveHour: 6, sevenDay: 1, extraUsage: nil)
        let fresh = [dup, dup2]
        let merged = archive.merge(fresh: fresh)
        #expect(merged == fresh)
    }

    @Test("İkinci birleştirme yalnızca yeni satırları aktarır")
    func mergeImportsOnlyNewRows() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = QuotaArchive(history: store)
        let first = [sample(300, fh: 1), sample(240, fh: 2)]
        _ = archive.merge(fresh: first)
        #expect(archive.stats.count == 2)

        // Eski bir satır arşivden silinse bile ikinci turda geri yazılmaz:
        // yalnızca en yeni aktarılandan sonrası gidiyor.
        _ = try store.prune(before: Date().addingTimeInterval(-270))
        #expect(archive.stats.count == 1)
        _ = archive.merge(fresh: first + [sample(60, fh: 3)])
        #expect(archive.stats.count == 2)
        #expect(try store.samples(since: .distantPast).map(\.fiveHour) == [2, 3])
    }

    @Test("Arşiv yoksa taze örnekler olduğu gibi döner")
    func nilHistoryReturnsFresh() {
        let archive = QuotaArchive(history: nil)
        let fresh = [sample(60, fh: 4)]
        #expect(archive.merge(fresh: fresh) == fresh)
        #expect(archive.recent(now: Date()).isEmpty)
        #expect(archive.stats.count == 0)
    }

    @Test("Penceresi eksik sunucu okuması arşive yazılmaz")
    func recordSkipsIncompleteUsage() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = QuotaArchive(history: store)

        let partial = ServerUsage(json: [
            "five_hour": ["utilization": 10.0] as [String: Any],
        ])
        archive.record(partial, at: Date(), org: "o")
        #expect(archive.stats.count == 0)

        let full = ServerUsage(json: [
            "five_hour": ["utilization": 10.0] as [String: Any],
            "seven_day": ["utilization": 20.0] as [String: Any],
        ])
        archive.record(full, at: Date(), org: "o")
        #expect(archive.stats.count == 1)
    }

    @Test("Profil 5 dakika içinde önbellekten döner")
    func profileIsCached() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = QuotaArchive(history: store)
        let now = Date()

        let first = archive.profile(now: now)
        #expect(first == .empty)

        // Arşive profil üretecek satırlar ekleniyor; önbellek süresi dolmadan
        // sonuç değişmemeli, dolduktan sonra değişmeli.
        let rows = (0..<12).map { i in
            QuotaSample(date: now.addingTimeInterval(Double(i - 12) * 300), org: "test",
                        fiveHour: i * 3, sevenDay: i, extraUsage: nil)
        }
        _ = try store.importSamples(rows)

        #expect(archive.profile(now: now.addingTimeInterval(4 * 60)) == .empty)
        #expect(archive.profile(now: now.addingTimeInterval(6 * 60)) != .empty)
    }

    @Test("Saklama süresi okunan en uzun dilimi kapsar, eski satırlar budanır")
    func pruneKeepsRetention() throws {
        #expect(QuotaArchive.retention >= QuotaArchive.profileSpan)
        #expect(QuotaArchive.retention >= QuotaArchive.recentSpan)

        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = QuotaArchive(history: store)
        let day: TimeInterval = 24 * 3600
        _ = try store.importSamples([
            sample(QuotaArchive.retention + day, fh: 1),
            sample(QuotaArchive.profileSpan, fh: 2),
            sample(60, fh: 3),
        ])

        archive.pruneIfDue(now: Date())
        let left = try store.samples(since: .distantPast)
        #expect(left.map(\.fiveHour) == [2, 3])
    }
}
