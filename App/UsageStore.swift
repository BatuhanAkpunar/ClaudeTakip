import AppKit
import Foundation
import Observation
import LimitCore

/// Arayüzün tek doğruluk kaynağı.
///
/// İki yerel kaynağı okur ve türetilmiş durumu yayınlar. Yoklama yoktur:
/// kota dosyası değiştiğinde sistem haber verir, aktivite taraması ise
/// pahalı olduğu için ayrı ve seyrek çalışır.
@MainActor
@Observable
final class UsageStore {
    private(set) var fiveHour: WindowPresentation?
    private(set) var weekly: WindowPresentation?
    private(set) var freshness: Freshness?
    private(set) var activity: ActivitySummary?
    private(set) var loadError: String?
    private(set) var account: Account?
    private(set) var serviceStatus: ServiceStatusReport?
    private(set) var isRefreshing = false
    /// Sayıların en son ne zaman tazelendiği. Verinin yaşından farklı bir şey:
    /// bu, uygulamanın dosyayı en son ne zaman okuduğunu söylüyor.
    private(set) var lastRefreshedAt = Date()
    /// Kota dosyasındaki `xu` alanının son değeri. Anlamı belgesiz olduğu için
    /// yalnızca ekstra kullanım açıkken yorumlanıyor.
    private(set) var latestExtraUsage: Int?

    /// Menü çubuğu çizimi için hazır anlık görüntü.
    /// Ayarlardaki "güncellemeleri denetle" düğmesi buraya bağlı; gerçek işi
    /// AppDelegate'teki Sparkle güncelleyici yapıyor. Test/önizlemede nil.
    var manualUpdateCheck: (() -> Void)?
    /// Güncelleyici bu derlemede var mı (yayında evet, DEBUG'da beslemesiz hayır).
    var updatesAvailable = false

    private(set) var menuBarSnapshot = MenuBarSnapshot(
        hasData: false, usedPercent: 0, countdownText: "", isStale: false
    )

    /// Durum değiştiğinde menü çubuğunun yeniden çizilmesi için.
    var onChange: (() -> Void)?

    /// Oturum durumu. Girişsizken uygulama yerel dosyalarla çalışmaya devam
    /// ediyor, giriş yalnızca sunucu doğruluğunu ve cüzdanı açıyor.
    enum AuthState: Equatable {
        case signedOut
        case signedIn
        case expired
    }

    private(set) var authState: AuthState = .signedOut
    private(set) var serverUsage: ServerUsage?
    private(set) var serverBalance: ClaudeWebClient.Balance?
    /// Sunucudan en son ne zaman okunduğu. Yerel dosya yoksa tazelik buna bağlanıyor.
    private(set) var lastServerFetch: Date?
    private(set) var serverError: String?

    private let sessionStore = SessionStore()
    private var session: SessionStore.Session?
    private var loginWindow: LoginWindowController?
    /// Oturum kuşağı: her giriş/çıkışta artıyor.
    ///
    /// Uçuştaki bir sunucu isteği tamamlandığında oturumun HÂLÂ aynı olduğunu
    /// doğrulamak için. Bu sayaç olmadan, çıkış yapıldıktan sonra dönen bir
    /// yanıt `authState`'i `.signedIn` yapıp oturum anahtarını diske geri
    /// yazıyordu: kullanıcı çıktığını sanıyor ama anahtar duruyordu.
    private var sessionGeneration = 0
    /// Yalnızca bir sunucu isteği uçuşta kalsın; yenisi öncekini iptal eder.
    /// Aksi halde elle yenileme ile 60 saniyelik tetik üst üste binip aynı
    /// alanlara sırasız yazıyordu.
    private var serverTask: Task<Void, Never>?
    /// Arka arkaya başarısız sunucu denemesi sayısı; üstel geri çekilmeyi besler.
    private var serverFailureStreak = 0
    /// Geçici ağ hatasından sonra yapılan kısa aralıklı sessiz denemeler.
    private var quickRetryTask: Task<Void, Never>?
    private var quickRetryCount = 0
    /// Bu andan önce yeni bir otomatik deneme yapılmıyor.
    ///
    /// Oturum düştüğünde çerez bilinçli olarak silinmiyor, ama 60 saniyelik
    /// tetik çalışmaya devam ettiği için uygulama ölü bir çerezle günde ~1440
    /// istek atıyordu. Ne kullanıcıya faydası var ne de sunucuya karşı nazik.
    private var nextServerAttempt: Date?
    /// Oturum düştüğünde giriş penceresi bu kuşakta bir kez kendiliğinden
    /// açıldı mı. theDanButuc her 401'de pencereyi zorla açıyor (Cloudflare
    /// 403'te sonsuz döngü); biz yalnızca etiket gösteriyorduk. Ortası: bir
    /// kez, sonra kullanıcıya bırak.
    private var autoSignInOffered = false

    /// Oturumun ne zaman dolacağı (çerezden). Arayüz 3 günden az kaldıysa uyarır.
    var sessionExpiresAt: Date? { session?.expiresAt }

    // MARK: - Pencere başlatma (opt-in)

    /// Pencere kapandığında kendiliğinden yeni pencere açma. Varsayılan AÇIK.
    ///
    /// Bu, uygulamanın kullanıcı hesabından içerik ürettiği tek özellik.
    /// Kontrol TEK yerde (`maybeStartSessionWindow`), böylece "kapattım ama
    /// yine de gönderiyor" durumu oluşamıyor: kapalıyken hiçbir yoldan istek
    /// çıkmıyor.
    var autoSessionEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoSessionEnabled") as? Bool ?? true
    }

    enum SessionStartState: Equatable {
        case idle
        case running
        case done(Date)
        case failed(String)
    }

    private(set) var sessionStartState: SessionStartState = .idle
    /// Son başlatma denemesi. Tekrar tekrar göndermeyi engelliyor.
    private var lastSessionStart: Date?
    /// İki deneme arasındaki en kısa süre. Sunucunun yeni pencereyi
    /// raporlaması birkaç tur sürebiliyor; bu aralık olmadan pencere açıkken
    /// bile üst üste istek gidiyordu.
    private static let sessionStartCooldown: TimeInterval = 10 * 60

    /// 5 saatlik pencere ŞU AN kapalı mı.
    ///
    /// claude.ai `resets_at` alanını yalnızca pencere açıkken döndürüyor;
    /// alan yoksa ya da geçmişteyse pencere kapalı demektir.
    var fiveHourWindowClosed: Bool {
        guard let window = serverUsage?.fiveHour else { return true }
        guard let resetsAt = window.resetsAt else { return true }
        return resetsAt <= Date()
    }

    /// Otomatik yol: yalnızca ayar AÇIKSA ve pencere gerçekten KAPALIYSA.
    /// Sabit aralıklı koşulsuz ping YOK; tetikleyici pencerenin kapalı olması.
    private func maybeStartSessionWindow() {
        guard autoSessionEnabled, fiveHourWindowClosed else { return }
        if let last = lastSessionStart,
           Date().timeIntervalSince(last) < Self.sessionStartCooldown { return }
        beginSessionWindow()
    }

    private func beginSessionWindow() {
        guard authState == .signedIn, let session, let organizationID = session.organizationID else {
            sessionStartState = .failed(L.t("Giriş gerekiyor.", "Sign in required."))
            return
        }
        guard sessionStartState != .running else { return }

        lastSessionStart = Date()
        sessionStartState = .running
        let generation = sessionGeneration

        Task { [weak self] in
            let client = ClaudeWebClient(sessionKey: session.sessionKey)
            do {
                try await client.startSessionWindow(organizationID: organizationID)
                await MainActor.run {
                    guard let self, generation == self.sessionGeneration else { return }
                    self.sessionStartState = .done(Date())
                    // Yeni pencereyi hemen doğrula.
                    self.refreshServer(userInitiated: true)
                }
            } catch {
                await MainActor.run {
                    guard let self, generation == self.sessionGeneration else { return }
                    self.sessionStartState = .failed(
                        L.t("Pencere başlatılamadı.", "Could not start the window.")
                    )
                }
            }
        }
    }

    /// Arşiv ve bildirimler. Arşiv açılamazsa uygulama çalışmaya devam eder,
    /// yalnızca uzun geçmiş özelliği devre dışı kalır.
    private let history = try? HistoryStore()
    private let cloud = CloudSync()
    private let cloudStore = CloudStore()
    private(set) var cloudSummary: CloudSync.Summary?
    private(set) var cloudError: String?
    private var cloudSyncing = false
    private(set) var historyStats: (count: Int, oldest: Date?) = (0, nil)
    /// Kullanıcının kota tüketim alışkanlığı. Hem saat kadranını hem tahmini besliyor.
    private(set) var profile: UsageProfile = .empty

    /// Claude Desktop kurulu olmayan makineyi taklit etmek için kota dosyası
    /// yolu değiştirilebiliyor. Bu senaryo elle test edilemiyordu ve tam da
    /// orada bir hata vardı: uygulama sunucu verisi dururken hata gösteriyordu.
    #if DEBUG
    private let reader = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_NO_DESKTOP"] == "1"
        ? PlanUsageReader(url: URL(fileURLWithPath: "/nonexistent/plan-usage-history.json"))
        : PlanUsageReader()
    #else
    private let reader = PlanUsageReader()
    #endif
    private let accountReader = AccountReader()
    private let statusService = StatusService()
    private let deriver = WindowDeriver()
    private let projector = Projector()
    private var watcher: FileWatcher?
    private var ticker: Timer?
    private var statusTicker: Timer?
    private var serverTicker: Timer?
    private var cloudTicker: Timer?

    init() {
        account = accountReader.read()
        session = sessionStore.load()
        // Eski sürümlerin Keychain'e yazdığı oturum anahtarını bir kez temizle.
        // Artık okunmuyor; orada bırakmak hesaba tam erişim veren bir çerezi
        // kimsenin bilmediği bir yerde tutmak demek.
        if !UserDefaults.standard.bool(forKey: "purgedLegacyKeychain") {
            sessionStore.purgeLegacyKeychainItem()
            UserDefaults.standard.set(true, forKey: "purgedLegacyKeychain")
        }
        authState = session == nil ? .signedOut : .signedIn
        refreshQuota()
        refreshActivity()
        refreshStatus()
        refreshServer()
        startWatching()
        startTicking()
        syncCloud()
    }

    // MARK: - Bulut

    var cloudEnabled: Bool {
        UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true
    }

    /// Bulut kimliğini garantiler, yoksa kaydeder.
    private func ensureIdentity() async throws -> CloudIdentity {
        if let existing = cloudStore.identity { return existing }
        let fresh = try await cloud.register()
        cloudStore.save(identity: fresh)
        return fresh
    }

    /// Hesap kimliği öğrenildiğinde bir kez çalışan geçiş.
    ///
    /// Bulut verisinin kanonik sahibi cihaz değil hesap. Bu fonksiyon dört
    /// senaryoyu birden çözüyor:
    ///
    /// - Anonim → giriş: bu cihazın buluttaki anonim satırları `/v1/claim`
    ///   ile hesaba devrediliyor, hiç yüklenmemiş yerel satırlar da (senkron
    ///   kapalıyken birikenler) işaret sıfırlandığı için hesabın altına
    ///   gönderiliyor. Giriş öncesi geçmiş kaybolmuyor.
    /// - Aynı cihazda giriş: anahtar değişmediği için hiçbir şey yapılmıyor.
    /// - Yeni cihaz: hesabın buluttaki geçmişi indirilip yerel arşive
    ///   karışıyor.
    /// - Yeni cihazda önce anonim kullanım: ikisi birden, önce devir sonra
    ///   indirme.
    ///
    /// Mükerrer kayıt oluşmuyor: yerel arşivin birincil anahtarı zaman
    /// damgası, buluttaki tablonun anahtarı ise (cihaz, zaman).
    private func adoptAccount(organizationID: String) {
        let key = AccountKey.derive(organizationID: organizationID)
        guard AccountKey.isValid(key), cloudStore.accountKey != key else { return }

        cloudStore.save(accountKey: key)
        // Yükleme işareti sıfırlanıyor ki daha önce gönderilmemiş satırlar da
        // hesaba gitsin. Yükleme idempotent olduğu için tekrar göndermek
        // güvenli: aynı (cihaz, zaman) ikinci kez satır açmıyor.
        cloudStore.resetWatermark()
        guard cloudEnabled else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await ensureIdentity()
                try await cloud.claim(identity: identity, accountKey: key)
            } catch {
                // Devir başarısızsa veri kaybolmuyor: kaynak yerel arşiv,
                // bir sonraki turda yeniden denenir.
            }
            await MainActor.run {
                self.syncCloud()
                self.restoreFromCloud()
            }
        }
    }

    /// Yerel arşivi buluta yedekler.
    ///
    /// Tek yönlü: yerel kaynak, bulut kopya. Yalnızca son yüklemeden sonraki
    /// örnekler gönderiliyor, dolayısıyla her çalıştırma birkaç satır.
    /// Girişliyken satırlar hesap anahtarıyla etiketleniyor.
    func syncCloud() {
        guard cloudEnabled, !cloudSyncing, let history else { return }
        cloudSyncing = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await ensureIdentity()
                let accountKey = cloudStore.accountKey

                // İlk yüklemede geçmişin tamamı gidiyor, sonrasında yalnızca yenisi.
                let watermark = cloudStore.uploadedThrough ?? .distantPast
                let pending = ((try? history.samples(since: watermark)) ?? [])
                    .filter { $0.date > watermark }

                if !pending.isEmpty {
                    try await cloud.upload(pending, plan: account?.planLabel,
                                           identity: identity, accountKey: accountKey)
                    if let newest = pending.last?.date {
                        cloudStore.save(uploadedThrough: newest)
                    }
                }

                let summary = try await cloud.summary(identity: identity, accountKey: accountKey)
                await MainActor.run {
                    self.cloudSummary = summary
                    self.cloudError = nil
                    self.cloudSyncing = false
                }
            } catch CloudSync.SyncError.notRegistered {
                // Cihaz kaydı sunucuda yok. Kimliği atıp bir sonraki turda
                // yeniden kaydolunuyor; veri yerelde durduğu için kayıp yok.
                cloudStore.clear()
                await MainActor.run {
                    self.cloudError = L.t("Bulut kaydı yenileniyor.", "Renewing cloud registration.")
                    self.cloudSyncing = false
                }
            } catch {
                await MainActor.run {
                    self.cloudError = L.t("Buluta ulaşılamadı.", "Could not reach the cloud.")
                    self.cloudSyncing = false
                }
            }
        }
    }

    /// Buluttaki geçmişi yerel arşive geri yükler. Yeni makine senaryosu.
    ///
    /// Girişliyse hesabın tüm cihazlarındaki geçmiş geliyor. İçe aktarma
    /// mükerrer üretmiyor: arşivin birincil anahtarı zaman damgası, aynı an
    /// ikinci kez yazılmıyor.
    func restoreFromCloud() {
        guard let identity = cloudStore.identity, let history else { return }
        let accountKey = cloudStore.accountKey
        Task { [weak self] in
            guard let self else { return }
            let samples = (try? await cloud.download(
                since: .distantPast, identity: identity, accountKey: accountKey)) ?? []
            guard !samples.isEmpty else { return }
            _ = try? history.importSamples(samples)
            await MainActor.run {
                self.historyStats = history.stats()
                self.refreshQuota()
            }
        }
    }

    /// Buluttaki tüm veriyi siler ve senkronu kapatır.
    func eraseCloud() {
        guard let identity = cloudStore.identity else { return }
        let accountKey = cloudStore.accountKey
        Task { [weak self] in
            guard let self else { return }
            do {
                // Hesap anahtarı ŞART: girişliyken satırlar hesap kapsamında
                // ve anahtarsız istek hiçbirini silmiyor.
                _ = try await cloud.deleteEverything(identity: identity, accountKey: accountKey)
            } catch {
                // Geri alınamaz bir eylemin başarısızlığı sessizce başarı gibi
                // sunulmamalı. Kimlik KORUNUYOR: aksi halde silinecek satırların
                // sahibi yerelden silinip veri buluttta yetim kalıyor ve
                // kullanıcı bir daha deneyemiyordu.
                await MainActor.run {
                    self.cloudError = L.t(
                        "Bulut verisi silinemedi, hâlâ duruyor. Yeniden dene.",
                        "Could not delete cloud data, it is still there. Try again."
                    )
                }
                return
            }
            cloudStore.clear()
            await MainActor.run {
                self.cloudSummary = nil
                self.cloudError = nil
                UserDefaults.standard.set(false, forKey: "cloudSyncEnabled")
            }
        }
    }

    // MARK: - Oturum

    func signIn() {
        // Zaten açıksa ikinci pencere açılmıyor, olan öne getiriliyor.
        if let loginWindow {
            loginWindow.present()
            return
        }
        let controller = LoginWindowController(
            onSuccess: { [weak self] sessionKey, expiresAt in
                Task { @MainActor in self?.completeSignIn(sessionKey: sessionKey, expiresAt: expiresAt) }
            },
            // Kullanıcı vazgeçtiğinde de bırakılmalı: yalnızca başarıda
            // nil'lenince iptal edilen her giriş bir WKWebView'i canlı
            // tutuyordu.
            onDismiss: { [weak self] in
                Task { @MainActor in self?.loginWindow = nil }
            }
        )
        loginWindow = controller
        controller.present()
    }

    func signOut() {
        // Kuşağı önce artır: uçuştaki yanıt döndüğünde artık yazamasın.
        sessionGeneration += 1
        serverTask?.cancel()
        serverTask = nil
        cancelQuickRetry()
        loginWindow = nil
        sessionStore.clear()
        // Hesap anahtarı bırakılıyor: bundan sonraki kayıtlar yine anonim ve
        // cihaza ait. Buluttaki hesap geçmişi silinmiyor, yeniden giriş
        // yapıldığında olduğu gibi geri geliyor.
        cloudStore.save(accountKey: nil)
        session = nil
        serverUsage = nil
        serverBalance = nil
        serverError = nil
        authState = .signedOut
        refreshQuota()
    }

    private func completeSignIn(sessionKey: String, expiresAt: Date? = nil) {
        sessionGeneration += 1
        autoSignInOffered = false
        let saved = SessionStore.Session(sessionKey: sessionKey, organizationID: nil, expiresAt: expiresAt)
        sessionStore.save(saved)
        session = saved
        authState = .signedIn
        serverError = nil
        loginWindow = nil
        refreshServer()
    }

    /// Sunucudan gerçek kullanım tablosunu çeker.
    ///
    /// Bu, uygulamanın kullanıcı verisi için yaptığı tek ağ isteği ve yalnızca
    /// giriş yapıldığında çalışıyor. Girişsizken uygulama tamamen yerel kalıyor.
    func refreshServer(userInitiated: Bool = false) {
        guard let session else { return }
        // Geri çekilme yalnızca OTOMATİK turlar için: kullanıcı "yenile"ye
        // bastığında beklemesi gerektiği söylenmemeli, hemen denenmeli.
        if !userInitiated, let next = nextServerAttempt, Date() < next { return }
        if userInitiated { serverFailureStreak = 0; nextServerAttempt = nil; cancelQuickRetry() }
        let generation = sessionGeneration
        serverTask?.cancel()
        serverTask = Task { [weak self] in
            let client = ClaudeWebClient(sessionKey: session.sessionKey) { [weak self] rotated in
                Task { @MainActor in self?.adoptRotatedKey(rotated, generation: generation) }
            }
            do {
                let org: String
                if let cached = session.organizationID {
                    org = cached
                } else {
                    org = try await client.organizationID()
                }
                let usage = try await client.usage(organizationID: org)
                // Bakiye ayrı bir uçta ve en iyi çaba: gelmezse ana veriyi bekletmez.
                // `is_enabled` şartına bağlanmıyor: cüzdan kapalıyken de içinde
                // para kalmış olabiliyor ve kullanıcının asıl merak ettiği o.
                let balance = usage.wallet != nil
                    ? await client.balance(organizationID: org)
                    : nil
                await MainActor.run {
                    guard let self, generation == self.sessionGeneration, self.session != nil else { return }
                    self.serverUsage = usage
                    self.serverBalance = balance
                    self.serverError = nil
                    self.authState = .signedIn
                    self.serverFailureStreak = 0
                    self.nextServerAttempt = nil
                    self.cancelQuickRetry()
                    self.lastServerFetch = Date()
                    self.recordServerReading(usage, now: Date())
                    // Hesap kimliği artık biliniyor: bulut verisinin sahibi
                    // cihazdan hesaba geçiyor. İlk seferde bir kez çalışır.
                    self.adoptAccount(organizationID: org)
                    // Taze sunucu verisiyle karar: pencere kapalıysa ve ayar
                    // açıksa yeni pencere başlat.
                    self.maybeStartSessionWindow()
                    if session.organizationID == nil {
                        let updated = SessionStore.Session(
                            sessionKey: session.sessionKey,
                            organizationID: org
                        )
                        self.sessionStore.save(updated)
                        self.session = updated
                    }
                    self.refreshQuota()
                }
            } catch ClaudeWebClient.ClientError.sessionExpired {
                await MainActor.run {
                    guard let self, generation == self.sessionGeneration, self.session != nil else { return }
                    // Çerez silinmiyor: kullanıcı yeniden giriş yapana kadar
                    // uygulama yerel veriyle çalışmaya devam etsin.
                    self.authState = .expired
                    self.serverUsage = nil
                    self.serverError = L.t("Oturum düştü, yeniden giriş gerekiyor.", "Session expired, sign in again.")
                    // Ölü çerezle dakikada bir denemenin faydası yok: yeniden
                    // giriş yapılana kadar aralık açılıyor (30 dk tavan).
                    self.backOff()
                    self.refreshQuota()
                    if !self.autoSignInOffered {
                        self.autoSignInOffered = true
                        self.signIn()
                    }
                }
            } catch ClaudeWebClient.ClientError.cloudflareChallenge {
                await MainActor.run {
                    guard let self, generation == self.sessionGeneration, self.session != nil else { return }
                    // Oturum SAĞLAM. Kullanıcıya yeniden giriş dedirtmek onu
                    // çözmeyecek bir döngüye sokar, çünkü sorun kimlikte değil
                    // ağda: VPN, IP itibarı veya Cloudflare çerez uyuşmazlığı.
                    self.authState = .signedIn
                    self.serverError = L.t("Cloudflare doğrulaması engelledi. VPN kullanıyorsan kapatıp dene.", "Cloudflare blocked the request. If you are on a VPN, try turning it off.")
                    self.backOff()
                    self.refreshQuota()
                }
            } catch is CancellationError {
                // Yenisi başlatıldı ya da çıkış yapıldı: sessizce çekil.
            } catch {
                await MainActor.run {
                    guard let self, generation == self.sessionGeneration, self.session != nil else { return }
                    // Ağ hatası GÖSTERİLMİYOR.
                    //
                    // "Sunucuya ulaşılamadı" bir şerit açıyordu ama kullanıcıya
                    // yapacak bir şey vermiyordu: Wi-Fi'nin bir saniyeliğine
                    // düşmesi, uyanma anındaki ilk istek, geçici 5xx. Hepsi
                    // kendiliğinden geçiyor. Onun yerine 4 saniye arayla
                    // sessizce yeniden deneniyor; ekrandaki sayının yaşı zaten
                    // başlıkta yazıyor, yani veri bayatlarsa kullanıcı görüyor.
                    //
                    // Kullanıcının MÜDAHALE etmesi gereken iki hata hâlâ
                    // görünüyor: oturumun düşmesi (yeniden giriş) ve Cloudflare
                    // engeli (VPN). Onlar kendiliğinden geçmiyor.
                    self.serverError = nil
                    self.scheduleQuickRetry(generation: generation)
                }
            }
        }
    }

    /// Servis durumu HEM iyi HEM taze mi.
    ///
    /// Bayat bir rapor "iyi" sayılamaz: kesinti sırasında status sayfasına da
    /// ulaşılamıyor ve son bilinen rapor genelde "operational" olduğu için
    /// menü çubuğu tam da kesinti anında sorun yokmuş gibi görünüyordu.
    private var serviceStatusIsGood: Bool {
        guard let report = serviceStatus else { return true }
        guard Date().timeIntervalSince(report.checkedAt) <= 45 * 60 else { return true }
        return report.status == .operational
    }

    /// Sunucunun döndürdüğü yeni oturum anahtarını benimser.
    ///
    /// Kuşak DEĞİŞMİYOR: bu bir yeniden giriş değil, aynı oturumun devamı.
    /// Ama kuşak eşleşmiyorsa (arada çıkış yapıldıysa) yeni anahtar da yok
    /// sayılıyor; aksi halde çıkış sonrası dirilme yeniden açılırdı.
    private func adoptRotatedKey(_ key: String, generation: Int) {
        guard generation == sessionGeneration, let current = session, current.sessionKey != key else { return }
        let updated = SessionStore.Session(
            sessionKey: key, organizationID: current.organizationID,
            savedAt: Date(), expiresAt: current.expiresAt
        )
        sessionStore.save(updated)
        session = updated
    }

    /// Üstel geri çekilme: 1 → 2 → 5 → 15 → 30 dakika tavanı.
    ///
    /// Tavan yarım saat: oturum düştüğünde kullanıcı yeniden giriş yapana kadar
    /// beklemek zaten gerekiyor, ama uygulama tamamen sessizleşmemeli ki ağ
    /// geri geldiğinde kendi kendine toparlasın.
    /// Geçici ağ hatasından sonra kısa aralıklı sessiz deneme.
    ///
    /// 4 saniye × 5 deneme ≈ 20 saniyelik bir pencere: kopan bir bağlantının
    /// geri gelmesi için yeterli, sunucuyu döverek yormak için değil. Bu
    /// pencere de sonuç vermezse normal geri çekilme merdivenine düşülüyor
    /// (1 → 2 → 5 → 15 → 30 dakika), yine sessizce.
    private static let quickRetryDelay: Duration = .seconds(4)
    private static let quickRetryLimit = 5

    private func scheduleQuickRetry(generation: Int) {
        guard quickRetryCount < Self.quickRetryLimit else {
            quickRetryCount = 0
            backOff()
            return
        }
        quickRetryCount += 1
        quickRetryTask?.cancel()
        quickRetryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.quickRetryDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, generation == self.sessionGeneration, self.session != nil else { return }
                // `userInitiated` DEĞİL: sayaçları sıfırlamadan, yalnızca
                // isteği tekrar kuruyor.
                self.nextServerAttempt = nil
                self.refreshServer()
            }
        }
    }

    private func cancelQuickRetry() {
        quickRetryTask?.cancel()
        quickRetryTask = nil
        quickRetryCount = 0
    }

    private func backOff() {
        serverFailureStreak = min(serverFailureStreak + 1, 5)
        let minutes = [1.0, 2.0, 5.0, 15.0, 30.0][serverFailureStreak - 1]
        nextServerAttempt = Date().addingTimeInterval(minutes * 60)
    }

    /// Kullanıcının elle tetiklediği tam yenileme.
    func refreshAll() {
        isRefreshing = true
        account = accountReader.read()
        refreshQuota()
        refreshActivity(force: true)
        refreshStatus()
        refreshServer(userInitiated: true)
        // Dosya okuma milisaniyeler sürüyor; göstergenin hiç görünmeden kaybolması
        // "tıkladım ama bir şey olmadı" hissi veriyor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isRefreshing = false
            self?.onChange?()
        }
    }

    func refreshStatus() {
        Task { [weak self] in
            guard let self else { return }
            let report = await statusService.fetch()
            await MainActor.run {
                if let report { self.serviceStatus = report }
            }
        }
    }

    /// Kota dosyası ucuz: 3500 örnek yaklaşık 6 ms'de okunuyor, her değişimde
    /// yeniden okumak sorun değil.
    func refreshQuota() {
        let now = Date()
        do {
            let fresh = try reader.read()
            // Önce arşive yaz, sonra arşivden oku. Claude Desktop'ın dosyası
            // budandığında arşiv daha geriye gidiyor, dolayısıyla haftalık
            // eğri ve sıfırlanma zinciri dosya kısalsa bile eksilmiyor.
            let samples = archived(merging: fresh)
            // Pencere türetmesi ile TAHMİN beslemesi ayrı dilim ister.
            // Uzun dilim yalnızca kullanım profili (En Aktif Saatler) için.
            // Tahmin artık geçmişe bakmıyor: pace ve dolma anı pencere başından
            // bu yana ortalama hızdan geliyor.
            let longRange = longRangeSamples(now: now)
            profile = cachedProfile(from: longRange, now: now)

            fiveHour = deriver.derive(.fiveHour, from: samples, now: now).map { state in
                let corrected = serverCorrected(state, server: serverUsage?.fiveHour)
                return WindowPresentation.make(
                    state: state,
                    projection: projector.project(corrected, now: now),
                    samples: samples,
                    now: now,
                    server: serverUsage?.fiveHour
                )
            }
            weekly = deriver.derive(.sevenDay, from: samples, now: now).map { state in
                let corrected = serverCorrected(state, server: serverUsage?.sevenDay)
                return WindowPresentation.make(
                    state: state,
                    projection: projector.project(corrected, now: now),
                    samples: samples,
                    now: now,
                    server: serverUsage?.sevenDay
                )
            }
            latestExtraUsage = samples.last?.extraUsage
            // Tazelik, ekranda görünen sayının GELDİĞİ kaynağın yaşı olmalı.
            //
            // Girişliyken yüzdeler sunucudan geliyor ve dakikada bir
            // tazeleniyor; Claude Desktop'ın dosyası ise uygulama kapalıyken
            // hiç yazılmıyor. İkisi karıştığında yenile'ye basan kullanıcı
            // saniyeler önce alınmış bir sayının yanında "veri 12 dk" yazısını
            // görüyordu: etiket dosyanın yaşını söylüyor, sayı sunucudan
            // geliyordu.
            freshness = serverFreshness(now: now)
                ?? reader.lastModified().map { Freshness(lastUpdate: $0, now: now) }
            loadError = nil
        } catch PlanUsageReader.ReadError.fileNotFound {
            // Claude Desktop kurulu olmayabilir. Bu bir hata değil: giriş
            // yapılmışsa sunucu zaten kesin değerleri veriyor, arşiv de
            // geçmişi tutuyor. Yalnızca ikisi de yoksa gösterilecek bir şey kalmıyor.
            buildFromServerOnly(now: now)
        } catch PlanUsageReader.ReadError.unsupportedVersion(let version) {
            loadError = L.t("Kota dosyası tanınmayan bir sürümde (v\(version)).", "Quota file is an unrecognized version (v\(version)).")
            buildFromServerOnly(now: now, fallbackError: loadError)
        } catch {
            loadError = L.t("Kota dosyası okunamadı.", "Could not read the quota file.")
            buildFromServerOnly(now: now, fallbackError: loadError)
        }

        lastRefreshedAt = now
        rebuildMenuBarSnapshot(now: now)
        onChange?()
    }

    /// Aktivite taraması 1,8 GB arşivde yaklaşık 1 saniye sürüyor, arka planda çalışır.
    /// Aktivite taraması PAHALI: ~/.claude/projects altındaki tüm transcript
    /// dosyaları okunuyor ve bu makinede 2,3 saniye sürüyor (60 bin olay).
    ///
    /// İki koruma var. (1) Tek uçuş: popover her açılışta tetiklediği için
    /// üst üste binen taramalar cooperative pool'un birden çok thread'ini
    /// aynı işe harcıyordu. (2) Soğuma: sonuç dakikalar içinde kayda değer
    /// biçimde değişmiyor, her açılışta yeniden taramanın karşılığı yok.
    private var activityScanning = false
    private var lastActivityScan: Date?
    private static let activityCooldown: TimeInterval = 5 * 60

    func refreshActivity(force: Bool = false) {
        guard !activityScanning else { return }
        if !force, let last = lastActivityScan,
           Date().timeIntervalSince(last) < Self.activityCooldown {
            return
        }
        activityScanning = true
        Task.detached(priority: .utility) { [weak self] in
            let summary = TranscriptReader().summarize()
            await MainActor.run {
                guard let self else { return }
                self.activity = summary
                self.activityScanning = false
                self.lastActivityScan = Date()
            }
        }
    }

    /// Fable'ın haftalık pencereden tahmini payı.
    ///
    /// Model bazlı gerçek kota yalnızca OAuth katmanında var, o da kapalı.
    /// Bu değer yerel token payından türetiliyor.
    ///
    /// Pay MUTLAKA mevcut haftalık pencereye göre hesaplanmalı. Tüm arşiv
    /// üzerinden hesaplandığında aylar önceki Fable kullanımı bu haftanın
    /// kotasına yansıyor ve sunucu "hiç kullanmadın" derken uygulama yüzde
    /// gösteriyordu.
    /// Fable'ın haftalık kotası. ÖNCE sunucunun gerçek değeri, yoksa tahmin.
    ///
    /// Sunucu bunu `limits` dizisinde `weekly_scoped` + `scope.model` olarak
    /// veriyor; uzun süre okunamadığı için kart yerel token payından türetilen
    /// tahmini gösteriyordu ve gerçek %4 iken %0 yazıyordu.
    var fableUsage: (percent: Double, isEstimate: Bool)? {
        if let real = serverUsage?.modelWindows.first(where: {
            $0.key.localizedCaseInsensitiveContains("fable")
        }) {
            return (real.value.utilization, false)
        }
        return fableEstimate.map { ($0, true) }
    }

    /// Fable kotasının sıfırlanma anı: sunucu verdiyse onunki.
    var fableResetsAt: Date? {
        serverUsage?.modelWindows.first(where: {
            $0.key.localizedCaseInsensitiveContains("fable")
        })?.value.resetsAt ?? weekly?.resetAt
    }

    /// Fable'ın haftalık pencereden tahmini payı (sunucu değeri yokken).
    var fableEstimate: Double? {
        guard let activity, let weekly, let start = weekly.windowStart else { return nil }
        guard let share = activity.share(matching: "claude-fable", since: start) else { return nil }
        return share * weekly.usedPercent
    }

    /// Cüzdanın durumu.
    ///
    /// İki kaynak var ve tazelikleri çok farklı: hesap dosyasındaki
    /// `hasExtraUsageEnabled` bayrağı profil önbelleğinden geliyor ve saatlerce
    /// eskiyebiliyor, kota dosyasındaki `xu` alanı ise beş dakikada bir
    /// tazeleniyor. Bu yüzden canlı sinyal bayrağı eziyor: `xu` görünüyorsa
    /// cüzdan açıktır, bayrak ne derse desin.
    var wallet: WalletState {
        // Sunucu verisi varsa tartışma yok: bayrak da bakiye de oradan geliyor.
        if let server = serverUsage?.wallet {
            return WalletState(
                isEnabled: server.isEnabled,
                // Sunucu kapalı diyorsa sebebi hesap dosyasında yazıyor olabilir;
                // orada da yoksa genel ifadeye düşülüyor.
                disabledReason: server.isEnabled
                    ? nil
                    : (account?.extraUsageDisabledText ?? L.t("ekstra kullanım kapalı", "extra usage is off")),
                consumedPercent: server.utilization,
                spendLimitReached: server.spendLimitReached,
                monthlyLimit: server.monthlyLimit,
                usedCredits: server.usedCredits,
                remainingBalance: serverBalance?.remaining,
                currency: server.currency,
                autoReloadEnabled: serverBalance?.autoReloadEnabled ?? false,
                isFromStaleCache: false,
                cachedAt: nil
            )
        }

        let liveSignal = latestExtraUsage != nil

        guard let account else {
            return WalletState(
                isEnabled: liveSignal,
                disabledReason: nil,
                consumedPercent: latestExtraUsage.map(Double.init),
                isFromStaleCache: !liveSignal,
                cachedAt: nil
            )
        }

        let enabled = liveSignal || account.hasExtraUsage
        return WalletState(
            isEnabled: enabled,
            disabledReason: enabled ? nil : account.extraUsageDisabledText,
            consumedPercent: latestExtraUsage.map(Double.init),
            // Canlı sinyal varsa önbelleğin yaşı önemsiz.
            isFromStaleCache: !liveSignal && account.isProfileStale,
            cachedAt: account.profileFetchedAt
        )
    }

    /// Taze örnekleri arşive aktarır ve pencere hesapları için gereken aralığı
    /// arşivden döner.
    ///
    /// Arşiv erişilemezse taze örneklerle devam ediliyor: kalıcı geçmiş bir
    /// iyileştirme, uygulamanın çalışma şartı değil.
    private func archived(merging fresh: [QuotaSample]) -> [QuotaSample] {
        guard let history else { return fresh }
        _ = try? history.importSamples(fresh)
        historyStats = history.stats()

        // Haftalık pencere en fazla 7 gün; 9 gün sıfırlanma zincirini de kapsıyor.
        let cutoff = Date().addingTimeInterval(-9 * 24 * 3600)
        guard let stored = try? history.samples(since: cutoff) else { return fresh }

        // Kıyas AYNI aralık üzerinden yapılmalı. Dokuz günlük arşiv dilimini
        // yirmi dokuz günlük dosyanın tamamıyla karşılaştırmak, arşivin hiçbir
        // zaman seçilmemesine ve özelliğin ölü kalmasına yol açıyordu.
        let freshInWindow = fresh.filter { $0.date >= cutoff }
        return stored.count >= freshInWindow.count ? stored : fresh
    }

    /// Yerel kota dosyası okunamadığında pencereleri sunucudan ve arşivden kurar.
    ///
    /// Claude Desktop kurulu olmayan bir kullanıcı için normal yol bu: yüzdeler
    /// ve sıfırlanma anları sunucudan geliyor, eğrinin geçmişi ise uygulamanın
    /// kendi arşivinden. Arşiv ilk günlerde boş olur ve zamanla dolar.
    private func buildFromServerOnly(now: Date, fallbackError: String? = nil) {
        guard let serverUsage else {
            loadError = fallbackError
                ?? L.t("Kullanım verisi yok. Giriş yap ya da Claude Desktop'ı kur.", "No usage data. Sign in or install Claude Desktop.")
            clearWindows()
            return
        }

        let samples = (try? history?.samples(since: now.addingTimeInterval(-9 * 24 * 3600))) ?? []
        fiveHour = serverUsage.fiveHour.flatMap { window -> WindowPresentation? in
            guard let resetsAt = window.resetsAt else { return nil }
            let state = WindowState.fromServer(kind: .fiveHour, utilization: window.utilization, resetsAt: resetsAt)
            return WindowPresentation.make(
                state: state,
                projection: projector.project(state, now: now),
                samples: samples,
                now: now,
                server: window
            )
        }
        weekly = serverUsage.sevenDay.flatMap { window -> WindowPresentation? in
            guard let resetsAt = window.resetsAt else { return nil }
            let state = WindowState.fromServer(kind: .sevenDay, utilization: window.utilization, resetsAt: resetsAt)
            return WindowPresentation.make(
                state: state,
                projection: projector.project(state, now: now),
                samples: samples,
                now: now,
                server: window
            )
        }
        latestExtraUsage = serverUsage.wallet?.utilization.map { Int($0.rounded()) }
        // Tazelik sunucu okumasına bağlanıyor: yerel dosya yoksa onun yaşı da yok.
        freshness = Freshness(lastUpdate: lastServerFetch ?? now, now: now)
        loadError = fallbackError
    }


    /// Projeksiyon için pencereyi sunucunun kesin sınırlarıyla düzeltir.
    ///
    /// Pencere ilk kullanımla başlıyor; bu doğru ve değişmiyor. Sorun ölçümde:
    /// yerel türetme "ilk kullanım"ı ancak yüzde ölçülebilir hale gelince
    /// görüyor. İlk mesajlar limitin binde birini harcadıysa yüzde bir süre 0
    /// kalıyor ve başlangıç saatlerce geç işaretleniyor. Gerçek örnek: sunucu
    /// pencerenin 09:59'da başladığını söylüyordu, yerel türetme 11:39 diyordu;
    /// 1 saat 40 dakikalık bu fark paydayı yarıya indirip hızı iki katına
    /// çıkarıyordu (pencere sonunda %23 yerine %43).
    ///
    /// `resets_at − pencere boyu` aynı anın kesin hâli, o yüzden varsa o
    /// kullanılıyor. Gösterimle hesap da böylece aynı pencereye bakıyor.
    private func serverCorrected(_ state: WindowState, server: ServerUsage.Window?) -> WindowState {
        guard let resetsAt = server?.resetsAt else { return state }
        let utilization = Int(server?.utilization.rounded() ?? Double(state.utilization))
        return WindowState(
            kind: state.kind,
            utilization: utilization,
            windowStart: resetsAt.addingTimeInterval(-state.kind.duration),
            resetAt: resetsAt,
            startUncertainty: 0,
            isIdle: utilization <= 0,
            observedResets: state.observedResets
        )
    }

    /// Sunucu ekrandaki sayıların kaynağıysa, tazelik son sunucu okumasının yaşı.
    /// Kaynak sunucu değilse nil dönüp yerel dosyanın yaşına bırakıyor.
    private func serverFreshness(now: Date) -> Freshness? {
        guard authState == .signedIn, serverUsage != nil, let fetched = lastServerFetch else {
            return nil
        }
        return Freshness(lastUpdate: fetched, now: now)
    }

    /// Sunucudan gelen okumayı arşive yazar.
    ///
    /// Bu olmadan, Claude Desktop kurulu olmayan bir kullanıcıda arşiv hiç
    /// dolmuyor ve grafikler sonsuza kadar boş kalıyordu.
    private func recordServerReading(_ usage: ServerUsage, now: Date) {
        guard let history,
              let five = usage.fiveHour,
              let seven = usage.sevenDay
        else { return }

        let sample = QuotaSample(
            date: now,
            org: session?.organizationID ?? "server",
            fiveHour: Int(five.utilization.rounded()),
            sevenDay: Int(seven.utilization.rounded()),
            extraUsage: usage.wallet?.utilization.map { Int($0.rounded()) }
        )
        _ = try? history.importSamples([sample])
        historyStats = history.stats()
    }

    /// Profil ve davranış tahmini için uzun dilim: arşivin son 60 günü.
    ///
    /// Hem saatlik desen hem haftalık birikim eğrisi ne kadar çok güne
    /// yayılırsa o kadar güvenilir; dokuz günlük dilimde haftalık davranış
    /// modeli hiç kurulamıyor.
    ///
    /// Sonuç önbellekleniyor: okuma 0,6 ms ama profil inşası 7,2 ms ve bu iş
    /// 30 saniyede bir ana iş parçacığında yapılıyordu. Arşiv büyüdükçe
    /// doğrusal artıyor, oysa saatlik desen dakikalar içinde değişmiyor.
    private var longRangeCache: (samples: [QuotaSample], at: Date)?
    private var profileCache: (profile: UsageProfile, at: Date)?
    private static let longRangeTTL: TimeInterval = 5 * 60

    private func longRangeSamples(now: Date) -> [QuotaSample] {
        if let cache = longRangeCache, now.timeIntervalSince(cache.at) < Self.longRangeTTL {
            return cache.samples
        }
        guard let history else { return [] }
        let cutoff = now.addingTimeInterval(-60 * 24 * 3600)
        let rows = (try? history.samples(since: cutoff)) ?? []
        longRangeCache = (rows, now)
        return rows
    }

    private func cachedProfile(from samples: [QuotaSample], now: Date) -> UsageProfile {
        if let cache = profileCache, now.timeIntervalSince(cache.at) < Self.longRangeTTL {
            return cache.profile
        }
        let built = UsageProfile.build(from: samples)
        profileCache = (built, now)
        return built
    }

    private func clearWindows() {
        fiveHour = nil
        weekly = nil
    }

    /// Menü çubuğu 5 saatlik pencereyi gösterir.
    ///
    /// Kullanıcı spec'i §2 net: menü çubuğunda haftalık kullanım gösterilmez,
    /// oraya yalnızca anlık durum ve kalan süre çıkar.
    private func rebuildMenuBarSnapshot(now: Date) {
        let isStale = freshness?.isStale ?? false

        guard let window = fiveHour else {
            menuBarSnapshot = MenuBarSnapshot(
                hasData: false, usedPercent: 0, countdownText: "", isStale: isStale,
                serviceOK: serviceStatusIsGood
            )
            return
        }

        // Haftalık geri sayım: pencere yoksa ya da sıfırlanma bekleniyorsa boş.
        let weeklyCountdown: String = {
            guard let weekly, !weekly.isAwaitingReset, !weekly.isIdle else { return "" }
            return Format.compactCountdown(remaining(of: weekly, now: now))
        }()

        menuBarSnapshot = MenuBarSnapshot(
            hasData: true,
            usedPercent: window.usedPercent,
            weeklyPercent: weekly?.usedPercent ?? 0,
            // Sıfırlanma beklenirken geri sayım "0d" olurdu; yanlış bilgi
            // vermektense o alan boş bırakılıyor.
            countdownText: window.isAwaitingReset
                ? ""
                : Format.clockCountdown(remaining(of: window, now: now)),
            weeklyCountdownText: weeklyCountdown,
            isStale: isStale,
            serviceOK: serviceStatusIsGood
        )
    }

    private func remaining(of window: WindowPresentation, now: Date) -> TimeInterval {
        guard !window.isIdle, let resetAt = window.resetAt else { return 0 }
        return max(0, resetAt.timeIntervalSince(now))
    }

    private func startWatching() {
        let candidate = FileWatcher(url: reader.url) { [weak self] in
            Task { @MainActor in self?.refreshQuota() }
        }
        // Kurulamadıysa referansı tutmuyoruz ki 30 saniyelik tur yeniden
        // denesin. Dosya Claude Desktop ilk çalıştığında oluşuyor.
        watcher = candidate.isWatching ? candidate : nil
    }

    /// Geri sayımların akması ve verinin yaşlandığının görülmesi için.
    /// Dosya değişmese bile kalan süre her dakika azalır.
    private func startTicking() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Dosya sonradan oluşmuş olabilir: izleyici yoksa yeniden kur.
                if self.watcher == nil { self.startWatching() }
                self.refreshQuota()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        // Sunucu okuması hem sayıları taze tutuyor hem de arşivi besliyor.
        // Beş dakika, Claude Desktop'ın kendi örnekleme aralığıyla aynı ve
        // topluluğun bu uç için güvenli bulduğu aralığın içinde.
        // Sunucu dakikada bir: kullanıcı "ne kadar kullandım" sorusunun
        // cevabını gecikmeli görmemeli. Tek bir hafif GET, kota tüketmiyor.
        let server = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshServer() }
        }
        RunLoop.main.add(server, forMode: .common)
        serverTicker = server

        // Uykudan uyanma: zamanlayıcılar uyku boyunca durur ve uyanınca bir
        // sonraki tura kadar (dakikalar) ekranda bayat veri kalır. Sistem
        // bildirimi bunu kapatıyor ve geri çekilme sayacını da sıfırlıyor:
        // uyku sırasında biriken hatalar uyanınca anlamsız.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.serverFailureStreak = 0
                self.nextServerAttempt = nil
                self.refreshQuota()
                self.refreshServer()
            }
        }

        // Servis durumu nadiren değişir, 15 dakikada bir yeterli.
        let status = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        RunLoop.main.add(status, forMode: .common)
        statusTicker = status

        // Bulut yedeği seyrek: her turda yalnızca birkaç yeni satır gidiyor
        // ve ücretsiz katmanın günlük istek bütçesini zorlamamak gerekiyor.
        let cloudTimer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncCloud() }
        }
        RunLoop.main.add(cloudTimer, forMode: .common)
        cloudTicker = cloudTimer
    }
}

/// Tek bir dosyanın değişimini dinler.
///
/// Claude Desktop dosyayı yerine yazdığı için hem `.write` hem `.rename` ve
/// `.delete` izlenir, silinme durumunda izleme yeniden kurulur.
@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
    }

    /// İzleme gerçekten kuruldu mu. Dosya henüz yoksa (Claude Desktop hiç
    /// çalışmamışsa) `open` başarısız oluyor ve izleyici sessizce ölü kalıyordu:
    /// dosya sonradan oluştuğunda bir daha bağlanmıyordu.
    var isWatching: Bool { source != nil }

    private func start() {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            onChange()
            // Dosya yerine yazıldıysa eski tanımlayıcı ölü kalır, yeniden bağlan.
            if events.contains(.rename) || events.contains(.delete) {
                restart()
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    private func restart() {
        source?.cancel()
        source = nil
        descriptor = -1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
            self?.onChange()
        }
    }
}
