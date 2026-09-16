import Foundation
import Security

/// Oturum anahtarını macOS Keychain'de saklar.
///
/// `sessionKey` tam yetkili bir hesap oturumudur: onu ele geçiren, kullanıcının
/// claude.ai hesabına girebilir. Dosya `0600` izniyle yalnızca aynı kullanıcının
/// diğer süreçlerinden korunmaz ve Time Machine yedeklerine düz metin gider.
/// Keychain hem şifreli hem de yedeklerde korunuyor.
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

    public func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    @discardableResult
    public func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Önce güncellemeyi dene: silip yeniden yazmak erişim listesini
        // sıfırlıyor ve kullanıcıya gereksiz izin penceresi çıkarabiliyor.
        //
        // Erişilebilirlik sınıfı güncellemede de veriliyor. Yalnızca
        // `SecItemAdd`'e konulduğunda, daha eski bir sürümün yazdığı kayıt
        // eski sınıfında kalıyor ve kimse fark etmiyordu.
        let updated = SecItemUpdate(
            baseQuery as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ] as CFDictionary
        )
        if updated == errSecSuccess { return true }

        var query = baseQuery
        query[kSecValueData as String] = data
        // `AfterFirstUnlock`, `WhenUnlocked` değil: uygulama giriş öğesi olarak
        // açılışta başlıyor ve ekran kilitliyken de arka planda kota yeniliyor.
        // `WhenUnlocked` ile kilitli ekranda anahtar okunamıyor, yenileme
        // sessizce başarısız oluyordu.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
