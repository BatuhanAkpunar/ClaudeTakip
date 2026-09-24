import Foundation
import Security

/// Eski sürümlerin Keychain'e yazdığı oturum kaydını silmek için; artık okunmaz ve yazılmaz.
public struct KeychainStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "Claude Limit", account: String = "claude.ai-session") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
