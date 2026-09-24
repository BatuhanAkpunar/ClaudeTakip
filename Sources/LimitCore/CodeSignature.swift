import Foundation
import Security

/// Yalnızca DEBUG kendi-testi için imza teşhisi; saklama kararını etkilemez.
public enum CodeSignature {
    /// Apple'ın `CS_ADHOC` bayrağı.
    private static let adhocFlag: UInt32 = 0x0000_0002

    /// Teşhis için ham değerler. Bayrak okunamadığında sebebini görebilmek şart:
    /// sessizce yanlış tarafa düşmek, oturum anahtarının hiçbir yere
    /// kaydedilmemesine yol açmıştı.
    ///
    /// `flagsRead`, bayrağın gerçekten okunup okunmadığı. Kendi-testi bunu
    /// kullanıyor; teşhis metnindeki Türkçe sözcükleri aramak metin
    /// değişince sessizce bozuluyordu.
    public static func inspect() -> (isUnstable: Bool, detail: String, flagsRead: Bool) {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return (true, "SecCodeCopySelf başarısız", false)
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return (true, "statik kod alınamadı", false) }

        // `kSecCodeInfoFlags` temel bilgi kümesinde gelmiyor; imza ayrıntıları
        // için `kSecCSSigningInformation` istenmeli. Bayrak verilmezse alan hiç
        // dönmez ve kod yanlış dala girer.
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return (true, "imza bilgisi alınamadı", false) }

        // Değer `NSNumber` olarak geliyor, doğrudan `UInt32`'ye köprülenmeyebilir.
        guard let raw = dictionary[kSecCodeInfoFlags as String] as? NSNumber else {
            let keys = dictionary.keys.sorted().prefix(6).joined(separator: ",")
            return (true, "flags alanı yok (anahtarlar: \(keys))", false)
        }

        let flags = raw.uint32Value
        let adhoc = flags & adhocFlag != 0
        return (adhoc, String(format: "flags=0x%x adhoc=%@", flags, adhoc ? "evet" : "hayır"), true)
    }
}
