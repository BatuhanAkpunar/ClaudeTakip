import Foundation
import SQLite3

/// Kota geçmişinin kalıcı arşivi.
///
/// Claude Desktop'ın dosyası yaklaşık 25 gün tutuyor ve ne kadar geriye
/// saklandığı bizim kontrolümüzde değil, bir gün budanabilir. Bu arşiv her
/// okumada yeni örnekleri kendi veritabanına aktarıyor, böylece geçmiş
/// uygulamaya ait oluyor.
///
/// SQLite doğrudan C arayüzüyle kullanılıyor: şema tek tablo ve tek indeksten
/// ibaret, bunun için harici bir bağımlılık eklemek gereksiz.
public final class HistoryStore: @unchecked Sendable {
    public enum StoreError: Error {
        case cannotOpen(String)
        case query(String)
    }

    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude Limit/history.sqlite")
    }

    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(url: URL = HistoryStore.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw StoreError.cannotOpen(url.path)
        }
        // Yazma sırasında okumayı engellememek için.
        exec("PRAGMA journal_mode=WAL;")
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func migrate() throws {
        // `t` birincil anahtar: aynı örnek iki kez yazılmıyor, dolayısıyla
        // içe aktarma işlemi kaç kez çalışırsa çalışsın sonuç aynı.
        try run("""
            CREATE TABLE IF NOT EXISTS quota_sample (
                t          INTEGER PRIMARY KEY,
                org        TEXT NOT NULL,
                five_hour  INTEGER NOT NULL,
                seven_day  INTEGER NOT NULL,
                extra      INTEGER
            );
            """)
        try run("CREATE INDEX IF NOT EXISTS quota_sample_t ON quota_sample(t);")
    }

    /// Yeni örnekleri arşive ekler, zaten olanları atlar. Eklenen sayıyı döner.
    @discardableResult
    public func importSamples(_ samples: [QuotaSample]) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }

        try run("BEGIN TRANSACTION;")
        // Aradaki her çıkış yolu işlemi kapatmalı. Açık kalan bir işlem
        // bağlantıyı kilitli bırakıyor ve sonraki her yazma başarısız oluyor.
        var committed = false
        defer { if !committed { try? run("ROLLBACK;") } }

        var statement: OpaquePointer?
        let sql = """
            INSERT OR IGNORE INTO quota_sample (t, org, five_hour, seven_day, extra)
            VALUES (?, ?, ?, ?, ?);
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.query(lastError)
        }
        defer { sqlite3_finalize(statement) }

        var inserted = 0
        for sample in samples {
            sqlite3_reset(statement)
            sqlite3_bind_int64(statement, 1, Int64(sample.date.timeIntervalSince1970 * 1000))
            // SQLITE_TRANSIENT: SQLite dizeyi kendi kopyalasın, aksi halde
            // Swift dizesi serbest bırakıldığında sarkan işaretçi kalıyor.
            sqlite3_bind_text(statement, 2, sample.org, -1, Self.transient)
            sqlite3_bind_int(statement, 3, Int32(sample.fiveHour))
            sqlite3_bind_int(statement, 4, Int32(sample.sevenDay))
            if let extra = sample.extraUsage {
                sqlite3_bind_int(statement, 5, Int32(extra))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            if sqlite3_step(statement) == SQLITE_DONE {
                inserted += Int(sqlite3_changes(db))
            }
        }
        try run("COMMIT;")
        committed = true
        return inserted
    }

    public func samples(since: Date) throws -> [QuotaSample] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        let sql = """
            SELECT t, org, five_hour, seven_day, extra FROM quota_sample
            WHERE t >= ? ORDER BY t ASC;
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.query(lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970 * 1000))

        var result: [QuotaSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(QuotaSample(
                date: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0)) / 1000),
                org: String(cString: sqlite3_column_text(statement, 1)),
                fiveHour: Int(sqlite3_column_int(statement, 2)),
                sevenDay: Int(sqlite3_column_int(statement, 3)),
                extraUsage: sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : Int(sqlite3_column_int(statement, 4))
            ))
        }
        return result
    }

    /// Arşivin kapsamı: kaç örnek ve en eskisi ne zaman.
    public func stats() -> (count: Int, oldest: Date?) {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*), MIN(t) FROM quota_sample;", -1, &statement, nil) == SQLITE_OK
        else { return (0, nil) }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return (0, nil) }
        let count = Int(sqlite3_column_int(statement, 0))
        let oldest = sqlite3_column_type(statement, 1) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 1)) / 1000)
        return (count, oldest)
    }

    // MARK: - Yardımcılar

    private static let transient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private var lastError: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "bilinmeyen hata"
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func run(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.query(lastError)
        }
    }
}
