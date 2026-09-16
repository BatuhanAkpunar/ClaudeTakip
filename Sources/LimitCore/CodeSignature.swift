import Foundation
import Security

/// Çalışan uygulamanın imza durumu.
///
/// Saklama kararı buna bağlı. Ad-hoc imza her derlemede değişiyor ve Keychain
/// erişim listesi imzaya bağlı olduğu için her yeni derleme kullanıcıya
/// "anahtarınıza erişmek istiyor" parola penceresi çıkarıyor. Gerçek bir
/// kimlikle imzalanmış derlemede imza sabit kalıyor ve bu sorun ortadan
/// kalkıyor.
public enum CodeSignature {
    /// Apple'ın `CS_ADHOC` bayrağı.
    private static let adhocFlag: UInt32 = 0x0000_0002

    /// Uygulama ad-hoc imzalı mı, yoksa hiç imzasız mı.
    ///
    /// İkisi de aynı sonucu doğuruyor: kararlı bir kimlik yok.
    public static var isUnstable: Bool { inspect().isUnstable }

    /// Teşhis için ham değerler. Bayrak okunamadığında sebebini görebilmek şart:
    /// sessizce yanlış tarafa düşmek, oturum anahtarının hiçbir yere
    /// kaydedilmemesine yol açmıştı.
    public static func inspect() -> (isUnstable: Bool, detail: String) {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return (true, "SecCodeCopySelf başarısız")
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return (true, "statik kod alınamadı") }

        // `kSecCodeInfoFlags` temel bilgi kümesinde gelmiyor; imza ayrıntıları
        // için `kSecCSSigningInformation` istenmeli. Bayrağı vermeden sorulunca
        // alan hiç dönmüyordu ve kod yanlış dala giriyordu.
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return (true, "imza bilgisi alınamadı") }

        // Değer `NSNumber` olarak geliyor, doğrudan `UInt32`'ye köprülenmeyebilir.
        guard let raw = dictionary[kSecCodeInfoFlags as String] as? NSNumber else {
            let keys = dictionary.keys.sorted().prefix(6).joined(separator: ",")
            return (true, "flags alanı yok (anahtarlar: \(keys))")
        }

        let flags = raw.uint32Value
        let adhoc = flags & adhocFlag != 0
        return (adhoc, String(format: "flags=0x%x adhoc=%@", flags, adhoc ? "evet" : "hayır"))
    }
}
