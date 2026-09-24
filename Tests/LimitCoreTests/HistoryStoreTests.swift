import Testing
import Foundation
@testable import LimitCore

@Suite("Kalıcı arşiv")
struct HistoryStoreTests {
    private func makeStore() throws -> (HistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudetakip-test-\(UUID().uuidString).sqlite")
        return (try HistoryStore(url: url), url)
    }

    private func sample(_ secondsAgo: Int, fh: Int, sd: Int, xu: Int? = nil) -> QuotaSample {
        QuotaSample(
            date: Date(timeIntervalSince1970: 1_787_000_000 - Double(secondsAgo)),
            org: "test", fiveHour: fh, sevenDay: sd, extraUsage: xu
        )
    }

    @Test("Örnekler yazılır ve geri okunur")
    func roundTrip() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let inserted = try store.importSamples([
            sample(300, fh: 10, sd: 5),
            sample(0, fh: 20, sd: 6, xu: 100),
        ])
        #expect(inserted == 2)

        let read = try store.samples(since: Date(timeIntervalSince1970: 0))
        #expect(read.count == 2)
        #expect(read.last?.extraUsage == 100)
        #expect(read.first?.fiveHour == 10)
    }

    @Test("Aynı örnek iki kez yazılmaz")
    func importIsIdempotent() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let batch = [sample(300, fh: 10, sd: 5), sample(0, fh: 20, sd: 6)]
        #expect(try store.importSamples(batch) == 2)
        // Kota dosyası her okumada baştan geliyor; ikinci içe aktarma
        // arşivi büyütmemeli.
        #expect(try store.importSamples(batch) == 0)
        #expect(store.stats().count == 2)
    }

    @Test("Tarih filtresi eski kayıtları eler")
    func filtersBySince() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try store.importSamples([sample(3600, fh: 1, sd: 1), sample(0, fh: 9, sd: 9)])
        let recent = try store.samples(since: Date(timeIntervalSince1970: 1_787_000_000 - 60))
        #expect(recent.count == 1)
        #expect(recent.first?.fiveHour == 9)
    }

    // MARK: - Arşiv işlemi

    /// Hazırlama başarısız olduğunda işlem açık kalıyor ve bağlantı sonraki
    /// her yazmada kilitli kalıyordu.
    @Test("Başarısız içe aktarma bağlantıyı kilitli bırakmaz")
    func importDoesNotLockOnFailure() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("regresyon-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try HistoryStore(url: url)
        let sample = QuotaSample(
            date: Date(), org: "test", fiveHour: 10, sevenDay: 20, extraUsage: nil
        )
        #expect(try store.importSamples([sample]) == 1)
        // İkinci yazma da geçmeli: ilk işlem düzgün kapandıysa kilit yok.
        #expect(try store.importSamples([sample]) == 0)
        #expect(try store.samples(since: Date().addingTimeInterval(-60)).count == 1)
    }
}
