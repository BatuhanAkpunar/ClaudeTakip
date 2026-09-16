import Foundation
import CryptoKit

/// Kullanım geçmişinin hesap kimliği.
///
/// Bulut verisinin kanonik sahibi cihaz değil HESAP olmalı: kullanıcı cihaz
/// değiştirdiğinde geçmişini kaybetmemeli. Ama hesabı adlandırmak için ham
/// organizasyon kimliğini sunucuya göndermek gereksiz bir ifşa.
///
/// Çözüm: organizasyon kimliğinin peppered SHA-256 özeti. Aynı Claude hesabı
/// her cihazda aynı anahtarı üretir, sunucu ise hangi hesap olduğunu asla
/// öğrenmez ve özetten geri dönemez.
///
/// Dürüst sınır: bu bir kimlik doğrulama değil, bir ADRES. Kimlik doğrulama
/// cihazın kendi gizli anahtarıyla yapılıyor; hesap anahtarı yalnızca verinin
/// hangi kovaya yazılacağını söylüyor. Organizasyon kimliğini bilen biri
/// teorik olarak aynı kovayı adresleyebilir; kovada yalnızca kullanım
/// yüzdeleri olduğu için bu bilinçli bir denge.
public enum AccountKey {
    /// Sabit tuz. Amacı, elinde aday organizasyon kimlikleri olan birinin
    /// özetleri doğrudan eşleştirmesini engellemek.
    private static let pepper = "claude-limit/account-scope/v1"

    /// 64 karakterlik onaltılık anahtar.
    public static func derive(organizationID: String) -> String {
        let trimmed = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data("\(pepper):\(trimmed)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Sunucunun kabul ettiği biçim: 64 onaltılık karakter.
    public static func isValid(_ key: String) -> Bool {
        key.count == 64 && key.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
