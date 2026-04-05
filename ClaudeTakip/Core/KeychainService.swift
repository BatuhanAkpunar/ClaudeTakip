import Foundation

/// File-based credential storage.
/// Stores data like session keys in ~/Library/Application Support/ClaudeTakip/.credentials
/// with 0600 permissions. Does not use Keychain — no password prompt.
struct KeychainService: Sendable {
    private static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClaudeTakip", isDirectory: true)
    }()

    private static let fileURL = directoryURL.appendingPathComponent(".credentials")

    func save(key: String, value: String) throws {
        var dict = loadAll()
        dict[key] = value
        try writeAll(dict)
    }

    func retrieve(key: String) throws -> String? {
        loadAll()[key]
    }

    func delete(key: String) throws {
        var dict = loadAll()
        dict.removeValue(forKey: key)
        if dict.isEmpty {
            try? FileManager.default.removeItem(at: Self.fileURL)
        } else {
            try writeAll(dict)
        }
    }

    // MARK: - Private

    private func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func writeAll(_ dict: [String: String]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.directoryURL.path) {
            try fm.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(dict)
        try data.write(to: Self.fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }
}
