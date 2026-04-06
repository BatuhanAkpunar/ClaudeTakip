import Foundation
import Security

/// File-based credential storage in Application Support.
/// Uses POSIX permissions (0600) for protection.
/// Avoids macOS Keychain entirely to prevent code-signature ACL prompts
/// that occur on every rebuild with ad-hoc signing.
struct KeychainService: Sendable {
    private static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ClaudeTakip", isDirectory: true)
    }()

    private static let credentialsURL = directoryURL.appendingPathComponent(".credentials")

    private func readStore() -> [String: String] {
        guard let data = try? Data(contentsOf: Self.credentialsURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func writeStore(_ dict: [String: String]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.directoryURL.path) {
            try fm.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(dict)
        try data.write(to: Self.credentialsURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.credentialsURL.path)
    }

    func save(key: String, value: String) throws {
        var dict = readStore()
        dict[key] = value
        try writeStore(dict)
    }

    func retrieve(key: String) throws -> String? {
        readStore()[key]
    }

    func delete(key: String) throws {
        var dict = readStore()
        dict.removeValue(forKey: key)
        try writeStore(dict)
    }
}

// MARK: - Migration

extension KeychainService {
    /// Migrates credentials from macOS Keychain to file-based storage (one-time).
    func migrateFromKeychainIfNeeded() {
        // Skip if file already has credentials
        if !readStore().isEmpty { return }

        let service = KeychainConstants.service
        let keys = [
            KeychainConstants.sessionKeyAccount,
            KeychainConstants.orgIdAccount,
            KeychainConstants.accountNameAccount,
            KeychainConstants.planNameAccount
        ]

        var migrated: [String: String] = [:]
        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let value = String(data: data, encoding: .utf8) {
                migrated[key] = value
            }
        }

        guard !migrated.isEmpty else { return }
        try? writeStore(migrated)

        // Clean up old keychain items
        for key in keys {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
