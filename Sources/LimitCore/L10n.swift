import Foundation

/// İki dilli metin katmanı.
///
/// Neden anahtar tabanlı `Localizable.strings` değil: uygulamanın tüm metni
/// iki dilde ve çağrı yerinde duruyor. Anahtar dosyası kurmak, her metin için
/// bir de isim uydurmayı ve iki dosyayı senkron tutmayı gerektirirdi; eksik
/// anahtar da ancak çalışma zamanında fark edilirdi. Burada iki karşılık yan
/// yana: derleyici birini unutmana izin vermiyor ve okurken hangi metnin
/// karşılığı olduğu görünüyor.
///
/// Dil değişimi anında: görünümler `@AppStorage("appLanguage")` okuduğu için
/// ayar değişince ağaç yeniden çiziliyor, uygulamayı kapatmak gerekmiyor.
public enum L {
    public enum Language: String, CaseIterable, Sendable {
        case system
        case turkish = "tr"
        case english = "en"

        public var label: (tr: String, en: String) {
            switch self {
            case .system: ("Sistem", "System")
            case .turkish: ("Türkçe", "Turkish")
            case .english: ("İngilizce", "English")
            }
        }
    }

    public static let storageKey = "appLanguage"

    /// Görev kapsamında dili sabitler; testler sistem dilinden ve kullanıcı
    /// ayarından bağımsız sonuç alabilsin diye.
    @TaskLocal public static var languageOverride: Language?

    /// Seçili dil. `system` ise işletim sisteminin tercih ettiği dile bakılır.
    static var current: Language {
        if let forced = languageOverride { return forced }
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? Language.system.rawValue
        let choice = Language(rawValue: raw) ?? .system
        guard choice == .system else { return choice }
        // Sistem Türkçe değilse İngilizce: uygulamanın yalnızca iki dili var,
        // tanımadığı bir dilde Türkçe göstermek İngilizceden daha kötü.
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("tr") ? .turkish : .english
    }

    public static var isTurkish: Bool { current == .turkish }

    /// Metin seçimi. Çağrı yerinde iki karşılık da görünür.
    public static func t(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }

    /// Tarih ve sayı biçimlendirmesi de dili takip etmeli: İngilizce arayüzde
    /// "5 Eyl" ya da "13,83" yazmak yarım çeviridir.
    public static var locale: Locale { Locale(identifier: isTurkish ? "tr_TR" : "en_US") }
}
