import Testing
import Foundation
import SQLite3
@testable import LimitCore

/// Diskte ve ayarlarda kalıcı olan biçimlerin altın testleri.
///
/// Bu dosyalar kullanıcının makinesinde sürümler arasında yaşıyor: bir alan
/// adı, bir tarih birimi ya da bir yol değişirse güncellemeden sonra oturum,
/// bulut kimliği veya geçmiş sessizce kaybolur. Buradaki sabitler bugünkü
/// kodun ürettiği ve okuduğu biçimin birebir kopyası; kod değiştiğinde
/// kırılmaları amaçlanıyor.
@Suite("Kalıcı biçimler")
struct PersistedFormatTests {

    // MARK: - Hesap anahtarı

    /// Anahtar sunucudaki kovanın adresi. Türetim değişirse aynı hesap başka
    /// bir kovaya yazmaya başlar ve eski geçmiş sahipsiz kalır.
    @Test("Hesap anahtarı sabit değerini korur")
    func accountKeyGolden() {
        #expect(AccountKey.derive(organizationID: "org-a")
            == "4caf451a76d11b0d77f415e4ba0218548ae969a405810e8a5f933425b81c7732")
        #expect(AccountKey.derive(organizationID: "00000000-0000-4000-8000-000000000001")
            == "a59ba7d6a0ab372480df1ab1ddf79890585aba5f5fe3133d854b04d674fe2483")
    }

    // MARK: - Oturum dosyası

    @Test("Oturum dosyası bugünkü alan adlarıyla okunur")
    func sessionFileLiteral() throws {
        let url = Self.temporaryURL("json")
        defer { try? FileManager.default.removeItem(at: url) }
        // `load()` Keychain'e hiç dokunmuyor; ayrı hizmet adı yine de gerçek
        // kaydın bu testten etkilenmemesini garanti ediyor.
        let store = SessionStore(
            url: url,
            keychain: KeychainStore(service: "ClaudeLimitTest", account: "golden")
        )

        try Data("""
            {"organizationID":"org-9","savedAt":800000000,"sessionKey":"sk-ant-sid02-abcdefghijklmnop"}
            """.utf8).write(to: url)
        let session = try #require(store.load())
        #expect(session.sessionKey == "sk-ant-sid02-abcdefghijklmnop")
        #expect(session.organizationID == "org-9")
        // Tarih `JSONEncoder`/`JSONDecoder` varsayılanıyla yazılıyor: 2001
        // referans tarihinden beri saniye, Unix epoch'tan değil.
        #expect(session.savedAt == Date(timeIntervalSinceReferenceDate: 800000000))
        #expect(session.expiresAt == nil)

        // Anahtarsız dosya oturum sayılmaz.
        try Data("""
            {"organizationID":"org-9","savedAt":800000000}
            """.utf8).write(to: url)
        #expect(store.load() == nil)
    }

    // MARK: - Bulut dosyası

    @Test("Bulut dosyası bugünkü alan adlarıyla okunur")
    func cloudFileLiteral() throws {
        let url = Self.temporaryURL("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let key = "4caf451a76d11b0d77f415e4ba0218548ae969a405810e8a5f933425b81c7732"

        try Data("""
            {"identity":{"deviceID":"d1","secret":"s1"},"uploadedThrough":800000000,"accountKey":"\(key)"}
            """.utf8).write(to: url)
        let store = CloudStore(url: url)
        #expect(store.identity == CloudIdentity(deviceID: "d1", secret: "s1"))
        #expect(store.uploadedThrough == Date(timeIntervalSinceReferenceDate: 800000000))
        #expect(store.accountKey == key)
    }

    // MARK: - Geçmiş arşivi

    /// `t` sütunu Unix epoch'tan beri MİLİSANİYE. Birim kayarsa eski arşiv
    /// ya boş görünür ya da 1970'e düşer.
    @Test("Geçmiş arşivi milisaniye sütununu iki yönde de korur")
    func historySqliteLiteral() throws {
        // Okuma: elle yazılmış bir satır bugünkü şemayla okunur.
        let readURL = Self.temporaryURL("sqlite")
        defer { Self.removeDatabase(at: readURL) }
        #expect(Self.rawExec(readURL, """
            CREATE TABLE quota_sample (
                t          INTEGER PRIMARY KEY,
                org        TEXT NOT NULL,
                five_hour  INTEGER NOT NULL,
                seven_day  INTEGER NOT NULL,
                extra      INTEGER
            );
            INSERT INTO quota_sample (t, org, five_hour, seven_day, extra)
            VALUES (1787344332573, 'o', 10, 20, NULL);
            """))

        let samples = try HistoryStore(url: readURL).samples(since: .distantPast)
        #expect(samples.count == 1)
        let sample = try #require(samples.first)
        #expect(abs(sample.date.timeIntervalSince1970 - 1787344332.573) < 0.0005)
        #expect(sample.org == "o")
        #expect(sample.fiveHour == 10)
        #expect(sample.sevenDay == 20)
        #expect(sample.extraUsage == nil)

        // Yazma: içe aktarılan örnek aynı tamsayıyla diske iner.
        let writeURL = Self.temporaryURL("sqlite")
        defer { Self.removeDatabase(at: writeURL) }
        do {
            // Depo bu blokta kapanıyor; ham okuma ayrı bir bağlantıyla yapılıyor.
            let store = try HistoryStore(url: writeURL)
            let written = QuotaSample(
                date: Date(timeIntervalSince1970: 1787344332.573),
                org: "o", fiveHour: 10, sevenDay: 20, extraUsage: nil
            )
            #expect(try store.importSamples([written]) == 1)
        }
        #expect(Self.rawIntegers(writeURL, "SELECT t FROM quota_sample;") == [1787344332573])
    }

    // MARK: - Claude Desktop geçmişi

    @Test("Claude Desktop geçmiş dosyası sürüm 2 şemasıyla okunur")
    func planUsageFixture() throws {
        let url = Self.temporaryURL("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = PlanUsageReader(url: url)

        // Üçüncü girdide `sd` yok: atlanır. Sıralama tarihe göre artan.
        try Data("""
            {"version":2,"samples":[{"t":2000,"org":"b","u":{"fh":5,"sd":6}},{"t":1000,"u":{"fh":1,"sd":2,"xu":3}},{"t":1500,"u":{"fh":9}}]}
            """.utf8).write(to: url)
        let samples = try reader.read()
        #expect(samples == [
            QuotaSample(date: Date(timeIntervalSince1970: 1), org: "",
                        fiveHour: 1, sevenDay: 2, extraUsage: 3),
            QuotaSample(date: Date(timeIntervalSince1970: 2), org: "b",
                        fiveHour: 5, sevenDay: 6, extraUsage: nil),
        ])

        try Data(#"{"version":3,"samples":[]}"#.utf8).write(to: url)
        #expect(Self.readError(reader) == PlanUsageReader.ReadError.unsupportedVersion(3))

        try Data(#"{"version":2}"#.utf8).write(to: url)
        switch Self.readError(reader) {
        case .malformed?: break
        case let other: Issue.record("malformed bekleniyordu, gelen: \(String(describing: other))")
        }

        let missing = Self.temporaryURL("json")
        #expect(Self.readError(PlanUsageReader(url: missing))
            == PlanUsageReader.ReadError.fileNotFound(missing))
    }

    // MARK: - Ayar anahtarı

    @Test("Dil tercihinin UserDefaults anahtarı sabit")
    func languageKey() {
        #expect(L.storageKey == "appLanguage")
    }

    // MARK: - Varsayılan yollar

    @Test("Varsayılan dosya yolları ev dizini altında sabit")
    func defaultPaths() {
        let home = NSHomeDirectory()
        let appSupport = "Library/Application Support/Claude Limit/"

        let cloud = CloudStore.defaultURL.path
        #expect(cloud.hasPrefix(home))
        #expect(cloud.hasSuffix(appSupport + "cloud.json"))

        let history = HistoryStore.defaultURL.path
        #expect(history.hasPrefix(home))
        #expect(history.hasSuffix(appSupport + "history.sqlite"))

        // `swift test` DEBUG derler; Release derlemesi ayrı dosyayı kullanır.
        let session = SessionStore.defaultURL.path
        #expect(session.hasPrefix(home))
        #if DEBUG
        #expect(session.hasSuffix(appSupport + "session-debug.json"))
        #else
        #expect(session.hasSuffix(appSupport + "session.json"))
        #endif

        let planUsage = PlanUsageReader.defaultURL.path
        #expect(planUsage.hasPrefix(home))
        #expect(planUsage.hasSuffix("Library/Application Support/Claude/plan-usage-history.json"))

        let account = AccountReader.defaultURL.path
        #expect(account.hasPrefix(home))
        #expect(account.hasSuffix(".claude.json"))

        let transcripts = TranscriptReader.defaultRoot.path
        #expect(transcripts.hasPrefix(home))
        #expect(transcripts.hasSuffix(".claude/projects"))
    }
}

// MARK: - Yardımcılar

extension PersistedFormatTests {
    fileprivate static func temporaryURL(_ pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalici-\(UUID().uuidString).\(pathExtension)")
    }

    /// WAL kipinin yan dosyaları da siliniyor.
    fileprivate static func removeDatabase(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    fileprivate static func readError(_ reader: PlanUsageReader) -> PlanUsageReader.ReadError? {
        do {
            _ = try reader.read()
            return nil
        } catch let error as PlanUsageReader.ReadError {
            return error
        } catch {
            return nil
        }
    }

    /// Depoyu atlayıp veritabanına doğrudan SQL yazar.
    fileprivate static func rawExec(_ url: URL, _ sql: String) -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// Depoyu atlayıp ilk sütunu tamsayı olarak okur.
    fileprivate static func rawIntegers(_ url: URL, _ sql: String) -> [Int64] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return [] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var values: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(sqlite3_column_int64(statement, 0))
        }
        return values
    }
}
