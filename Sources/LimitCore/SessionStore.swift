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
    public static var defaultURL: URL {
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude Limit")
        // Geliştirme derlemesi AYRI bir dosya kullanıyor.
        //
        // Release anahtarı Keychain'de tutuyor ve taşıma sırasında dosyadaki
        // düz metin kopyayı siliyor. İki derleme aynı dosyayı paylaştığında,
        // bir kez çalıştırılan bir Release aracı (ör. limitcheck) geliştirme
        // oturumunu da götürüyordu. Ayrı dosya ikisini birbirinden yalıtıyor;
        // kullanıcının kurduğu uygulama yalnızca Release yolunu görüyor.
        #if DEBUG
        return base.appendingPathComponent("session-debug.json")
        #else
        return base.appendingPathComponent("session.json")
        #endif
    }

    public let url: URL
    private let keychain: KeychainStore
    private let usesKeychain: Bool

    public init(url: URL = SessionStore.defaultURL, keychain: KeychainStore = KeychainStore()) {
        self.url = url
        self.keychain = keychain
        // Keychain HİÇBİR derlemede kullanılmıyor; alan yalnızca eski
        // kayıtların temizlenmesi için duruyor (`clear`).
        self.usesKeychain = false
    }

    public struct Session: Codable, Sendable, Equatable {
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
    }

    /// Diskte tutulan, gizli olmayan kısım.
    private struct Metadata: Codable {
        var organizationID: String?
        var savedAt: Date
        var expiresAt: Date?
        /// Yalnızca geliştirme derlemesinde dolu olur.
        var sessionKey: String?
    }

    public func load() -> Session? {
        // Keychain'e HİÇ dokunulmuyor, var olan kayıt için bile.
        //
        // `SecItemCopyMatching` erişim listesi eşleşmediğinde parola penceresi
        // AÇARAK başarısız oluyor; yani "bir kereliğine okuyup dosyaya taşıyalım"
        // çözümü tam da kaldırmak istediğimiz pencereyi açıyordu. Eski
        // sürümden gelen kullanıcı bir kez yeniden giriş yapıyor.
        let metadata = loadMetadata()
        guard let metadata, let key = metadata.sessionKey else { return nil }
        return Session(sessionKey: key, organizationID: metadata.organizationID,
                       savedAt: metadata.savedAt, expiresAt: metadata.expiresAt)
    }

    @discardableResult
    public func save(_ session: Session) -> Bool {
        var stored = true
        if usesKeychain {
            stored = keychain.save(session.sessionKey)
        }
        let metadata = Metadata(
            organizationID: session.organizationID,
            savedAt: session.savedAt,
            expiresAt: session.expiresAt,
            // Keychain kullanılıyorsa anahtar dosyaya HİÇ yazılmaz, aksi halde
            // taşımanın anlamı kalmaz.
            sessionKey: usesKeychain ? nil : session.sessionKey
        )
        return writeMetadata(metadata) && stored
    }

    /// Eski sürümlerin Keychain'de bıraktığı oturum anahtarını siler.
    ///
    /// Artık okunmuyor ama durduğu yerde duruyor: kullanıcının hesabına tam
    /// erişim veren bir çerez, kimsenin haberi olmadan anahtarlıkta kalıyor.
    /// `SecItemDelete` veriyi OKUMADIĞI için erişim listesi eşleşmese de
    /// parola penceresi açmıyor; bu yüzden sessizce temizlenebiliyor.
    public func purgeLegacyKeychainItem() {
        keychain.clear()
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
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(metadata)
            // `.completeFileProtection` KULLANILMIYOR: iOS'a ait bir dosya
            // koruma sınıfı ve macOS'ta yazmayı "Operation not permitted" ile
            // tamamen engelliyor. Oturum anahtarının hiç kaydedilmemesinin
            // sebebi buydu. Koruma POSIX 0600 ile sağlanıyor.
            try data.write(to: url, options: [.atomic])
            // Atomik yazım dosyayı yeniden yarattığı için izinler sonradan konuyor.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
