import Foundation

/// Uygulamanın UserDefaults'a yazdığı anahtarlar ve varsayılanları.
///
/// Bu dizeler kalıcı biçimin parçası: değişirse mevcut kurulumların ayarları
/// sessizce varsayılana döner. Testler her dizeyi birebir sabitler.
public enum SettingsKey {
    /// 5 saatlik pencereyi otomatik başlatma ayarı.
    public static let autoSessionEnabled = "autoSessionEnabled"
    /// Otomatik başlatmanın, kullanıcı hiç dokunmadıysa geçerli değeri.
    /// AÇIK: uygulamanın ana özelliklerinden biri. Kayıtlı açık bir değer
    /// (true ya da false) olduğu gibi korunur.
    public static let autoSessionDefault = true
    public static let cloudSyncEnabled = "cloudSyncEnabled"
    /// Eski Keychain kaydının bir kez temizlendiğini işaretler.
    public static let purgedLegacyKeychain = "purgedLegacyKeychain"
    /// ARTIK YAZILMIYOR: hiçbir yer okumuyordu. Eski kurulumlarda değer
    /// kalmış olabilir; kalıcı biçimin parçası olduğu için sabit duruyor.
    public static let showInMenuBar = "showInMenuBar"
}
