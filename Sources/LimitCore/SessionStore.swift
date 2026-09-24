import Foundation

/// Oturum bilgisini saklar.
///
/// Anahtar 0600 izinli bir dosyada tutuluyor, Keychain'de DEĞİL.
///
/// Keychain denendi ve geri alındı. Sebebi ölçüldü: Keychain erişim listesi
/// uygulamanın KOD İMZASINA bağlı. Uygulama Apple Developer hesabı olmadığı
/// için ad-hoc imzalanıyor ve ad-hoc imza her derlemede değişiyor. Kullanıcı
/// yeni bir sürüm kurduğunda macOS anahtarı yazan ikiliyi tanımıyor ve
/// "giriş anahtarlığı parolanızı girin" penceresi açılıyor — her güncellemede.
///
/// Bu yalnızca can sıkıcı değil, GÜVENLİK AÇISINDAN DA KÖTÜ: kullanıcıya
/// düzenli olarak sistem parolasını yazdırmak, tam olarak kimlik avının
/// dayandığı alışkanlığı öğretiyor. Karşılığında kazanılan koruma ise
/// görünürde: aynı kullanıcı olarak çalışan bir süreç zaten izin penceresini
/// tetikleyip kullanıcının "İzin ver"e basmasını bekleyebiliyor.
///
/// Dosyanın sınırı açıkça şu: aynı kullanıcı olarak çalışan başka bir süreç
/// onu okuyabilir ve Time Machine yedeğine şifresiz gider. Claude Desktop'ın
/// kendi `.credentials` dosyası da aynı sınıfta. Uygulama Developer ID ile
/// imzalanabildiği gün imza sabitleneceği için Keychain'e dönmek doğru olur;
/// o zamana kadar değil.
public struct SessionStore: Sendable {
    /// Yayın derlemesinin, yani kullanıcının kurduğu uygulamanın oturum dosyası.
    public static var releaseURL: URL {
        StoragePaths.appSupport.appendingPathComponent("session.json")
    }

    public static var defaultURL: URL {
        // Debug derlemesi ayrı dosya kullanır: geliştirme sırasında çıkış/clear,
        // kurulu Release uygulamasının oturumunu silmesin. Kullanıcının kurduğu
        // uygulama yalnızca Release yolunu görür.
        #if DEBUG
        return StoragePaths.appSupport.appendingPathComponent("session-debug.json")
        #else
        return releaseURL
        #endif
    }

    public let url: URL
    private let keychain: KeychainStore

    public init(url: URL = SessionStore.defaultURL, keychain: KeychainStore = KeychainStore()) {
        self.url = url
        // Keychain HİÇBİR derlemede okunmaz ve yazılmaz; alan yalnızca eski
        // kayıtların temizlenmesi için durur (`clear`).
        self.keychain = keychain
    }

    public struct Session: Sendable, Equatable {
        public let sessionKey: String
        public let organizationID: String?
        public let savedAt: Date
        /// Çerezin son kullanma tarihi. claude.ai bunu veriyor; yoksa bilinmiyor.
        public let expiresAt: Date?

        public init(sessionKey: String, organizationID: String?, savedAt: Date = Date(), expiresAt: Date? = nil) {
            self.sessionKey = sessionKey
            self.organizationID = organizationID
            self.savedAt = savedAt
            self.expiresAt = expiresAt
        }

        /// Yalnızca kuruluş kimliği değişmiş kopya. Anahtar, kayıt anı ve son
        /// kullanma tarihi korunur: sıfırdan `Session` kurmak `expiresAt`'i
        /// düşürüyor ve "oturum N gün sonra dolacak" uyarısı hiç çıkmıyordu.
        public func with(organizationID: String?) -> Session {
            Session(sessionKey: sessionKey, organizationID: organizationID,
                    savedAt: savedAt, expiresAt: expiresAt)
        }
    }

    public enum SessionExpiryWarning: Equatable, Sendable {
        case expired
        case expiresWithin(days: Int)
    }

    /// Çerezin dolmasına 3 günden az kaldıysa uyarı: Claude Code'un
    /// "login expires in 3 days" uyarısıyla aynı eşik. Gün sayısı yukarı
    /// yuvarlanır (71 saat → 3 gün).
    public static func expiryWarning(expiresAt: Date, now: Date = Date()) -> SessionExpiryWarning? {
        let left = expiresAt.timeIntervalSince(now)
        guard left < 3 * 24 * 3600 else { return nil }
        if left <= 0 { return .expired }
        return .expiresWithin(days: max(0, Int((left / 86400).rounded(.up))))
    }

    /// Diskte tutulan, gizli olmayan kısım.
    private struct Metadata: Codable {
        var organizationID: String?
        var savedAt: Date
        var expiresAt: Date?
        /// Eski sürümlerin yazdığı dosyada yoksa nil → oturum yok sayılır.
        var sessionKey: String?
    }

    public func load() -> Session? {
        // Keychain'e HİÇ dokunulmuyor, var olan kayıt için bile.
        //
        // `SecItemCopyMatching` erişim listesi eşleşmediğinde parola penceresi
        // AÇARAK başarısız oluyor; yani "bir kereliğine okuyup dosyaya taşıyalım"
        // çözümü tam da kaldırmak istediğimiz pencereyi açar. Eski sürümden
        // gelen kullanıcı bir kez yeniden giriş yapar.
        let metadata = loadMetadata()
        guard let metadata, let key = metadata.sessionKey else { return nil }
        return Session(sessionKey: key, organizationID: metadata.organizationID,
                       savedAt: metadata.savedAt, expiresAt: metadata.expiresAt)
    }

    @discardableResult
    public func save(_ session: Session) -> Bool {
        writeMetadata(Metadata(organizationID: session.organizationID, savedAt: session.savedAt,
                               expiresAt: session.expiresAt, sessionKey: session.sessionKey))
    }

    /// Eski sürümlerin Keychain'de bıraktığı oturum anahtarını siler.
    ///
    /// Okunmuyor ama durduğu yerde duruyor: kullanıcının hesabına tam
    /// erişim veren bir çerez, kimsenin haberi olmadan anahtarlıkta kalıyor.
    /// `SecItemDelete` veriyi OKUMADIĞI için erişim listesi eşleşmese de
    /// parola penceresi açmıyor; bu yüzden sessizce temizlenebiliyor.
    public func purgeLegacyKeychainItem() {
        keychain.clear()
    }

    /// `purgeLegacyKeychainItem`'ı kurulum başına bir kez çalıştırır; yapıldığını
    /// `SettingsKey.purgedLegacyKeychain` bayrağıyla işaretler.
    public func purgeLegacyKeychainItemOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: SettingsKey.purgedLegacyKeychain) else { return }
        purgeLegacyKeychainItem()
        defaults.set(true, forKey: SettingsKey.purgedLegacyKeychain)
    }

    public func clear() {
        // Eski sürümlerin bıraktığı Keychain kaydı da siliniyor. `SecItemDelete`
        // erişim listesi eşleşmese bile parola sormadan siliyor (silmek veriyi
        // OKUMAYI gerektirmiyor), yani çıkış yapmak pencere açmıyor.
        keychain.clear()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Dosya

    private func loadMetadata() -> Metadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    private func writeMetadata(_ metadata: Metadata) -> Bool {
        do {
            try PrivateFile.write(JSONEncoder().encode(metadata), to: url)
            return true
        } catch {
            return false
        }
    }
}
