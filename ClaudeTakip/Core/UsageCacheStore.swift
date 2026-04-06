import Foundation
import os.log

// MARK: - Cache Models

struct UsageBucket: Codable, Sendable {
    var utilization: Double     // 0-1 (API returns 0-100, divided by 100 during recording)
    var resetsAt: Date?
}

struct ExtraUsageInfo: Codable, Sendable {
    var isEnabled: Bool
    var monthlyLimit: Double?   // in cents
    var usedCredits: Double?    // in cents
    var utilization: Double?    // 0-100
    var currentBalance: Double? // in cents
    var autoReload: Bool?
}

struct CachedUsage: Codable, Sendable {
    var fiveHour: UsageBucket?
    var sevenDay: UsageBucket?
    var sevenDaySonnet: UsageBucket?
    var extraUsage: ExtraUsageInfo?
}

struct UsageCacheFile: Codable, Sendable {
    var version: Int = 1
    var lastUpdate: Date?
    var current: CachedUsage = .init()
    var sessionHistory: [UsageSnapshot] = []
    var weeklyHistory: [UsageSnapshot] = []
    var sonnetHistory: [UsageSnapshot] = []
}

// MARK: - Cache Store

@MainActor
final class UsageCacheStore {
    private static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ClaudeTakip", isDirectory: true)
    }()

    private static let legacyFileURL = directoryURL.appendingPathComponent("usage-cache.json")

    private var orgId: String?

    private(set) var cache = UsageCacheFile()
    private var pendingWrites = 0
    private let batchThreshold = 5
    private var lastWriteDate: Date?
    private static let maxFlushInterval: TimeInterval = 300 // 5 minutes

    private static let maxSessionHistory = 100
    private static let maxWeeklyHistory = 500
    private static let maxModelHistory = 200

    private func fileURL() -> URL {
        if let orgId {
            return Self.directoryURL.appendingPathComponent("usage-cache-\(orgId).json")
        }
        return Self.legacyFileURL
    }

    // MARK: - Configure

    /// Sets the active orgId, migrates legacy data if needed, and loads the cache.
    func configure(orgId: String) {
        self.orgId = orgId
        migrateLegacyFileIfNeeded(orgId: orgId)
        load()
    }

    /// Resets in-memory state without writing to disk (used on sign-out).
    func clearInMemory() {
        cache = UsageCacheFile()
        pendingWrites = 0
        lastWriteDate = nil
        orgId = nil
    }

    // MARK: - Load

    func load() {
        migrateFromUserDefaultsIfNeeded()
        guard let data = try? Data(contentsOf: fileURL()),
              let file = try? JSONDecoder.withISO8601.decode(UsageCacheFile.self, from: data)
        else { return }
        cache = file
    }

    /// One-time migration: rename unscoped legacy file to orgId-scoped file.
    private func migrateLegacyFileIfNeeded(orgId: String) {
        let fm = FileManager.default
        let legacy = Self.legacyFileURL
        let scoped = Self.directoryURL.appendingPathComponent("usage-cache-\(orgId).json")
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: scoped.path) else { return }
        try? fm.moveItem(at: legacy, to: scoped)
    }

    /// One-time migration from UserDefaults to file-based system
    private func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        let oldKeys = [
            "claudekota_usage_history",
            "claudekota_history_reset_date",
            "claudekota_weekly_history",
            "claudekota_weekly_reset_date",
            "claudekota_sonnet_history",
            "claudekota_sonnet_reset_date"
        ]
        guard oldKeys.contains(where: { ud.object(forKey: $0) != nil }) else { return }

        // Read old data — UserDefaults uses epoch-based dates
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .deferredToDate

        if let data = ud.data(forKey: "claudekota_usage_history"),
           let history = try? legacyDecoder.decode([UsageSnapshot].self, from: data) {
            cache.sessionHistory = history
        }
        if let data = ud.data(forKey: "claudekota_weekly_history"),
           let history = try? legacyDecoder.decode([UsageSnapshot].self, from: data) {
            cache.weeklyHistory = history
        }
        if let data = ud.data(forKey: "claudekota_sonnet_history"),
           let history = try? legacyDecoder.decode([UsageSnapshot].self, from: data) {
            cache.sonnetHistory = history
        }

        // Write to new file
        writeToDisk()

        // Clean up old keys
        for key in oldKeys {
            ud.removeObject(forKey: key)
        }
    }

    // MARK: - Update Current

    func updateCurrent(_ usage: CachedUsage) {
        cache.current = usage
        cache.lastUpdate = Date()
        markDirty()
    }

    // MARK: - Record Snapshots

    func recordSessionSnapshot(usage: Double) {
        cache.sessionHistory.append(UsageSnapshot(timestamp: Date(), usage: usage))
        trimIfNeeded(&cache.sessionHistory, max: Self.maxSessionHistory)
        markDirty()
    }

    func recordWeeklySnapshot(usage: Double) {
        cache.weeklyHistory.append(UsageSnapshot(timestamp: Date(), usage: usage))
        trimIfNeeded(&cache.weeklyHistory, max: Self.maxWeeklyHistory)
        markDirty()
    }

    func recordSonnetSnapshot(usage: Double) {
        cache.sonnetHistory.append(UsageSnapshot(timestamp: Date(), usage: usage))
        trimIfNeeded(&cache.sonnetHistory, max: Self.maxModelHistory)
        markDirty()
    }

    // MARK: - Clear

    func clearSessionHistory() {
        cache.sessionHistory.removeAll()
        forceFlush()
    }

    func clearWeeklyHistory() {
        cache.weeklyHistory.removeAll()
        forceFlush()
    }

    func clearSonnetHistory() {
        cache.sonnetHistory.removeAll()
        forceFlush()
    }

    // MARK: - Flush

    func forceFlush() {
        pendingWrites = 0
        writeToDisk()
    }

    // MARK: - Private

    private func markDirty() {
        pendingWrites += 1
        let shouldFlush = pendingWrites >= batchThreshold
            || (lastWriteDate.map { Date().timeIntervalSince($0) >= Self.maxFlushInterval } ?? true)
        if shouldFlush {
            pendingWrites = 0
            writeToDisk()
        }
    }

    private func trimIfNeeded(_ array: inout [UsageSnapshot], max limit: Int) {
        if array.count > limit {
            array.removeFirst(array.count - limit)
        }
    }

    private func writeToDisk() {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: Self.directoryURL.path) {
                try fm.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            }
            let url = fileURL()
            let data = try JSONEncoder.withISO8601.encode(cache)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastWriteDate = Date()
        } catch {
            Logger(subsystem: "com.batuhanakpunar.ClaudeTakip", category: "cache")
                .error("Cache write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - JSON Coders

private extension JSONEncoder {
    static let withISO8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let withISO8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
