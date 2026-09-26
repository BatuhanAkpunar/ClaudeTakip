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
    private var activity: ActivitySummary?
    private(set) var loadError: String?
    private(set) var account: Account?
    private(set) var serviceStatus: ServiceStatusReport?
    private(set) var isRefreshing = false
    /// Sayıların en son ne zaman tazelendiği. Verinin yaşından farklı bir şey:
    /// bu, uygulamanın dosyayı en son ne zaman okuduğunu söylüyor.
    private(set) var lastRefreshedAt = Date()
    /// Kota dosyasındaki `xu` alanının son değeri. Anlamı belgesiz olduğu için
    /// yalnızca ekstra kullanım açıkken yorumlanıyor.
    private var latestExtraUsage: Int?

    /// Ayarlardaki "güncellemeleri denetle" düğmesi buraya bağlı; gerçek işi
    /// AppDelegate'teki Sparkle güncelleyici yapıyor. Test/önizlemede nil.
    var manualUpdateCheck: (() -> Void)?
    /// Güncelleyici bu derlemede var mı (yayında evet, DEBUG'da beslemesiz hayır).
    var updatesAvailable = false

    /// Menü çubuğu çizimi için hazır anlık görüntü.
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
    private var serverUsage: ServerUsage?
    private var serverBalance: ClaudeWebClient.Balance?
    /// Sunucudan en son ne zaman okunduğu. Yerel dosya yoksa tazelik buna bağlanıyor.
    private var lastServerFetch: Date?
    private(set) var serverError: String?

    private let sessionStore = SessionStore()
    private var session: SessionStore.Session?
    private var loginWindow: LoginWindowController?
    /// Oturum kuşağı: her giriş/çıkışta artıyor.
    ///
    /// Uçuştaki bir sunucu isteği tamamlandığında oturumun HÂLÂ aynı olduğunu
    /// doğrulamak için. Bu sayaç olmadan, çıkış yapıldıktan sonra dönen bir
    /// yanıt `authState`'i `.signedIn` yapıp oturum anahtarını diske geri
    /// yazar: kullanıcı çıktığını sanır ama anahtar durur.
    private var sessionGeneration = 0
    /// Yalnızca bir sunucu isteği uçuşta kalsın; yenisi öncekini iptal eder.
    /// Aksi halde elle yenileme ile 60 saniyelik tetik üst üste binip aynı
    /// alanlara sırasız yazar.
    private var serverTask: Task<Void, Never>?
    /// Geri çekilme ve kısa deneme durumu (bkz. `ServerRetryPolicy`).
    private var retry = ServerRetryPolicy()
    /// Geçici ağ hatasından sonra yapılan kısa aralıklı sessiz denemeler.
    private var quickRetryTask: Task<Void, Never>?
    /// Oturum düştüğünde giriş penceresi bu kuşakta bir kez kendiliğinden
    /// açıldı mı. theDanButuc her 401'de pencereyi zorla açıyor (Cloudflare
    /// 403'te sonsuz döngü); yalnızca etiket göstermek ise kullanıcıyı
    /// çıkışsız bırakır. Ortası: bir kez, sonra kullanıcıya bırak.
    private var autoSignInOffered = false

    /// Oturumun ne zaman dolacağı (çerezden). Arayüz 3 günden az kaldıysa uyarır.
    var sessionExpiresAt: Date? { session?.expiresAt }

    // MARK: - Pencere başlatma (varsayılan kapalı)

    /// Hesaptan içerik üreten tek özellik; onay ve koşullar orada
    /// (bkz. `SessionWindowStarter`).
    private let starter: SessionWindowStarter

    typealias SessionStartState = SessionWindowStarter.State

    private(set) var sessionStartState: SessionStartState = .idle

    /// 5 saatlik pencere ŞU AN kapalı mı.
    ///
    /// claude.ai `resets_at` alanını yalnızca pencere açıkken döndürüyor;
    /// alan yoksa ya da geçmişteyse pencere kapalı demektir.
    private var fiveHourWindowClosed: Bool {
        serverUsage?.fiveHour?.isClosed(at: Date()) ?? true
    }

    /// Otomatik yol: yalnızca ayar AÇIKSA ve pencere gerçekten KAPALIYSA
    /// (bkz. `SessionWindowStarter.startIfNeeded`).
    private func maybeStartSessionWindow() {
        let generation = sessionGeneration
        starter.startIfNeeded(
            windowClosed: fiveHourWindowClosed,
            credentials: authState == .signedIn
                ? session.flatMap { s in s.organizationID.map { (sessionKey: s.sessionKey, organizationID: $0) } }
                : nil,
            isCurrent: { [weak self] in self?.sessionGeneration == generation },
            onStarted: { [weak self] in self?.refreshServer(userInitiated: true) }
        )
    }

    /// Kota arşivi; tüm SQLite erişimi burada. Arşiv açılamazsa uygulama
    /// çalışmaya devam eder, yalnızca uzun geçmiş özelliği devre dışı kalır.
    private let archive: QuotaArchive
    /// Bulut yedeği (kimlik, hesaba devir, yükleme işaretleri).
    private let cloudBackup: CloudBackup
    /// Arşivin satır sayısı ve en eski kaydı; istendiğinde arşivden okunur.
    var historyStats: (count: Int, oldest: Date?) { archive.stats }
    /// Kullanıcının kota tüketim alışkanlığı. Hem saat kadranını hem tahmini besliyor.
    private(set) var profile: UsageProfile = .empty

    /// Claude Desktop kurulu olmayan makineyi taklit etmek için kota dosyası
    /// yolu değiştirilebiliyor; bu senaryo elle test edilemiyor. Beklenen:
    /// sunucu verisi dururken hata gösterilmez.
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
    /// Zamanlayıcılar, uyanma gözlemcisi ve dosya izleyicisi.
    private var scheduler: RefreshScheduler?

    init() {
        let history = try? HistoryStore()
        self.archive = QuotaArchive(history: history)
        self.cloudBackup = CloudBackup(history: history)
        self.starter = SessionWindowStarter()
        starter.onChange = { [weak self] state in self?.sessionStartState = state }
        account = accountReader.read()
        session = sessionStore.load()
        // Eski sürümlerin Keychain'e yazdığı oturum anahtarını bir kez temizle.
        // Artık okunmuyor; orada bırakmak hesaba tam erişim veren bir çerezi
        // kimsenin bilmediği bir yerde tutmak demek.
        sessionStore.purgeLegacyKeychainItemOnce()
        authState = session == nil ? .signedOut : .signedIn
        refreshQuota()
        refreshActivity()
        refreshStatus()
        refreshServer()
        scheduler = RefreshScheduler(
            watchedFile: reader.url,
            onTick: { [weak self] in self?.refreshQuota() },
            onServer: { [weak self] in self?.refreshServer() },
            onStatus: { [weak self] in self?.refreshStatus() },
            onCloud: { [weak self] in self?.cloudBackup.sync() },
            onWake: { [weak self] in
                guard let self else { return }
                self.retry.clearBackoff()
                self.starter.resetAfterWake()
                self.refreshQuota()
                // Ölü keep-alive bağlantıları önce bırakılıyor; yoksa uyanıştaki
                // ilk istek uyku öncesi sokete gidip düşer.
                Task { @MainActor [weak self] in
                    await ClaudeWebClient.dropPooledConnections()
                    self?.refreshServer()
                }
            },
            onFileChange: { [weak self] in self?.refreshQuota() }
        )
        scheduler?.start()
        cloudBackup.planLabel = { [weak self] in self?.account?.planLabel }
        cloudBackup.onRestored = { [weak self] in self?.refreshQuota() }
        cloudBackup.sync()
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
            // nil'lenirse iptal edilen her giriş bir WKWebView'i canlı
            // tutar.
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
        starter.cancel()
        // Açık bir giriş penceresi varsa ekranda kalmasın; yalnızca
        // referansı bırakmak pencereyi kapatmıyor.
        loginWindow?.close()
        loginWindow = nil
        sessionStore.clear()
        // Hesap anahtarı bırakılıyor: bundan sonraki kayıtlar yine anonim ve
        // cihaza ait. Buluttaki hesap geçmişi silinmiyor, yeniden giriş
        // yapıldığında olduğu gibi geri geliyor.
        cloudBackup.releaseAccount()
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
        // Kullanıcı eylemi sayılıyor: eski oturumun 401/Cloudflare geri
        // çekilmesi yeni oturumun ilk okumasını 30 dakikaya kadar bekletmesin.
        refreshServer(userInitiated: true)
    }

    /// Sunucudan gerçek kullanım tablosunu çeker.
    ///
    /// Bu, uygulamanın kullanıcı verisi için yaptığı tek ağ isteği ve yalnızca
    /// giriş yapıldığında çalışıyor. Girişsizken uygulama tamamen yerel kalıyor.
    func refreshServer(userInitiated: Bool = false) {
        guard let session else { return }
        // Geri çekilme yalnızca OTOMATİK turlar için: kullanıcı "yenile"ye
        // bastığında beklemesi gerektiği söylenmemeli, hemen denenmeli.
        if !userInitiated, !retry.allowsAutomaticAttempt(at: Date()) { return }
        if userInitiated { retry.clearBackoff(); cancelQuickRetry() }
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
                guard let self, self.isCurrent(generation) else { return }
                self.applyServerSuccess(usage: usage, balance: balance, org: org, fetchedWith: session)
            } catch ClaudeWebClient.ClientError.sessionExpired {
                guard let self, self.isCurrent(generation) else { return }
                self.applySessionExpired()
            } catch ClaudeWebClient.ClientError.cloudflareChallenge {
                guard let self, self.isCurrent(generation) else { return }
                self.applyCloudflareBlock()
            } catch is CancellationError {
                // Yenisi başlatıldı ya da çıkış yapıldı: sessizce çekil.
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.applyTransientFailure(generation: generation)
            }
        }
    }

    /// Başarılı sunucu okuması. Adımların SIRASI önemli.
    ///
    /// `session`, isteğin başladığı andaki oturum; yalnızca güncel oturum
    /// yoksa yedek olarak kullanılır.
    private func applyServerSuccess(
        usage: ServerUsage,
        balance: ClaudeWebClient.Balance?,
        org: String,
        fetchedWith session: SessionStore.Session
    ) {
        serverUsage = usage
        serverBalance = balance
        serverError = nil
        authState = .signedIn
        retry.clearBackoff()
        cancelQuickRetry()
        lastServerFetch = Date()
        // Kuruluş kimliği ÖNCE kaydediliyor: arşiv etiketi ve otomatik
        // başlatma onu okuyor. Sonra kaydedilseydi girişten sonraki ilk okuma
        // "server" etiketiyle arşivlenir, otomatik başlatma da "Giriş
        // gerekiyor." derdi. Temel, isteği başlatan kopya değil GÜNCEL oturum:
        // istek sırasında döndürülmüş anahtar eskisiyle ezilmesin.
        let current = self.session ?? session
        if current.organizationID == nil {
            let updated = current.with(organizationID: org)
            sessionStore.save(updated)
            self.session = updated
        }
        archive.record(usage, at: Date(), org: self.session?.organizationID ?? "server")
        // Hesap kimliği biliniyor: bulut verisinin sahibi
        // cihazdan hesaba geçiyor. İlk seferde bir kez çalışır.
        cloudBackup.adopt(organizationID: org)
        // Taze sunucu verisiyle karar: pencere kapalıysa ve ayar
        // açıksa yeni pencere başlat.
        maybeStartSessionWindow()
        refreshQuota()
    }

    private func applySessionExpired() {
        // Çerez silinmiyor: kullanıcı yeniden giriş yapana kadar
        // uygulama yerel veriyle çalışmaya devam etsin.
        authState = .expired
        serverUsage = nil
        serverError = L.t("Oturum düştü, yeniden giriş gerekiyor.", "Session expired, sign in again.")
        // Ölü çerezle dakikada bir denemenin faydası yok: yeniden
        // giriş yapılana kadar aralık açılıyor (30 dk tavan).
        retry.backOff(now: Date())
        refreshQuota()
        if !autoSignInOffered {
            autoSignInOffered = true
            signIn()
        }
    }

    private func applyCloudflareBlock() {
        // Oturum SAĞLAM. Kullanıcıya yeniden giriş dedirtmek onu
        // çözmeyecek bir döngüye sokar, çünkü sorun kimlikte değil
        // ağda: VPN, IP itibarı veya Cloudflare çerez uyuşmazlığı.
        authState = .signedIn
        serverError = L.t("Cloudflare doğrulaması engelledi. VPN kullanıyorsan kapatıp dene.", "Cloudflare blocked the request. If you are on a VPN, try turning it off.")
        retry.backOff(now: Date())
        refreshQuota()
    }

    private func applyTransientFailure(generation: Int) {
        // Ağ hatası GÖSTERİLMİYOR.
        //
        // "Sunucuya ulaşılamadı" şeridi kullanıcıya yapacak bir şey
        // vermez: Wi-Fi'nin bir saniyeliğine düşmesi, uyanma anındaki ilk
        // istek, geçici 5xx. Hepsi kendiliğinden geçiyor. Onun yerine 4
        // saniye arayla sessizce yeniden deneniyor; ekrandaki sayının yaşı
        // zaten başlıkta yazıyor, yani veri bayatlarsa kullanıcı görüyor.
        //
        // Kullanıcının MÜDAHALE etmesi gereken iki hata görünüyor: oturumun
        // düşmesi (yeniden giriş) ve Cloudflare engeli (VPN). Onlar
        // kendiliğinden geçmiyor.
        serverError = nil
        scheduleQuickRetry(generation: generation)
    }

    /// Menü çubuğu kesinti rengini yalnızca TAZE ve sağlıksız bir rapor için
    /// gösterir. Rapor yoksa ya da bayatsa (`ServiceStatusReport.staleAfter`)
    /// true döner: bayat raporun "şu an" hakkında söylediği bir şey yok.
    private var serviceStatusIsGood: Bool {
        guard let report = serviceStatus, !report.isStale() else { return true }
        return report.status.isHealthy
    }

    /// Yanıt hâlâ aynı oturuma mı ait: kuşak değişmediyse ve çıkış yapılmadıysa.
    private func isCurrent(_ generation: Int) -> Bool {
        generation == sessionGeneration && session != nil
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

    /// Geçici ağ hatasından sonra kısa aralıklı sessiz deneme; sayı ve
    /// aralık `ServerRetryPolicy`'de.
    private func scheduleQuickRetry(generation: Int) {
        guard retry.recordTransientFailure(now: Date()) == .retrySoon else { return }
        quickRetryTask?.cancel()
        quickRetryTask = Task { [weak self] in
            try? await Task.sleep(for: ServerRetryPolicy.quickRetryDelay)
            guard !Task.isCancelled else { return }
            guard let self, self.isCurrent(generation) else { return }
            // `userInitiated` DEĞİL: sayaçları sıfırlamadan, yalnızca
            // isteği tekrar kuruyor.
            self.retry.bypassBackoffOnce()
            self.refreshServer()
        }
    }

    private func cancelQuickRetry() {
        quickRetryTask?.cancel()
        quickRetryTask = nil
        retry.resetQuickRetries()
    }

    /// Buluttaki veriyi siler ve yedeklemeyi kapatır (bkz. `CloudBackup.eraseCloud`).
    func eraseCloudData() async -> Bool {
        await cloudBackup.eraseCloud()
    }

    /// Kullanıcının elle tetiklediği tam yenileme.
    /// Her elle yenilemede artıyor: üst üste basışlarda göstergeyi yalnızca
    /// SON basışın zamanlayıcısı kapatsın.
    private var refreshAllGeneration = 0

    func refreshAll() {
        refreshAllGeneration += 1
        let generation = refreshAllGeneration
        isRefreshing = true
        account = accountReader.read()
        refreshQuota()
        refreshActivity(force: true)
        refreshStatus()
        refreshServer(userInitiated: true)
        // Dosya okuma milisaniyeler sürüyor; göstergenin hiç görünmeden kaybolması
        // "tıkladım ama bir şey olmadı" hissi veriyor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.refreshAllGeneration == generation else { return }
            self.isRefreshing = false
            self.onChange?()
        }
    }

    private func refreshStatus() {
        Task { [weak self] in
            guard let self else { return }
            let report = await statusService.fetch()
            guard let report else { return }
            self.serviceStatus = report
            // Kesinti rengi menü çubuğunda hemen görünsün; bir sonraki
            // 30 saniyelik turu beklemesin.
            self.rebuildMenuBarSnapshot(now: Date())
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
            let samples = archive.merge(fresh: fresh)
            // Pencere türetmesi ile TAHMİN beslemesi ayrı dilim ister.
            // Uzun dilim yalnızca kullanım profili (En Aktif Saatler) için.
            // Tahmin geçmişe bakmıyor: pace ve dolma anı pencere başından
            // bu yana ortalama hızdan geliyor.
            profile = archive.profile(now: now)

            fiveHour = derivedWindow(.fiveHour, samples: samples, now: now)
            weekly = derivedWindow(.sevenDay, samples: samples, now: now)
            latestExtraUsage = samples.last?.extraUsage
            // Tazelik, ekranda görünen sayının GELDİĞİ kaynağın yaşı olmalı.
            //
            // Girişliyken yüzdeler sunucudan geliyor ve dakikada bir
            // tazeleniyor; Claude Desktop'ın dosyası ise uygulama kapalıyken
            // hiç yazılmıyor. İkisi karışırsa yenile'ye basan kullanıcı
            // saniyeler önce alınmış bir sayının yanında "veri 12 dk" yazısını
            // görür: etiket dosyanın yaşını söyler, sayı sunucudan gelir.
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
    }

    /// Menü çubuğu anlık görüntüsünü mevcut durumdan yeniden kurar.
    private func rebuildMenuBarSnapshot(now: Date) {
        menuBarSnapshot = .make(fiveHour: fiveHour, weekly: weekly, freshness: freshness,
                                serviceOK: serviceStatusIsGood, now: now)
        onChange?()
    }

    /// Aktivite taraması PAHALI: ~/.claude/projects altındaki tüm transcript
    /// dosyaları okunuyor ve bu makinede 2,3 saniye sürüyor (60 bin olay), bu
    /// yüzden arka planda çalışır.
    ///
    /// İki koruma var. (1) Tek uçuş: popover her açılışta tetiklediği için
    /// üst üste binen taramalar cooperative pool'un birden çok thread'ini
    /// aynı işe harcar. (2) Soğuma: sonuç dakikalar içinde kayda değer
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
        // Task.detached DEĞİL, GCD kuyruğu: `summarize` içerde
        // `concurrentPerform` ile saniyelerce bloke oluyor ve cooperative
        // pool'un sınırlı iş parçacıklarından birini o süre boyunca işgal
        // ediyordu. Bloke eden iş GCD'de, sonuç ana aktöre dönüyor.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let summary = TranscriptReader().summarize()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activity = summary
                self.activityScanning = false
                self.lastActivityScan = Date()
            }
        }
    }

    /// Fable'ın haftalık kotası. ÖNCE sunucunun gerçek değeri, yoksa tahmin.
    ///
    /// Sunucu bunu `limits` dizisinde `weekly_scoped` + `scope.model` olarak
    /// veriyor. Tahmin yerel token payından türetilir ve sunucu değerinden
    /// sapabilir (gerçek %4 iken %0 görülebilir); bu yüzden yalnızca yedek.
    var fableUsage: (percent: Double, isEstimate: Bool)? {
        if let real = serverUsage?.modelWindow(matching: "fable") {
            return (real.utilization, false)
        }
        return fableEstimate.map { ($0, true) }
    }

    /// Fable kotasının sıfırlanma anı: sunucu verdiyse onunki.
    var fableResetsAt: Date? {
        serverUsage?.modelWindow(matching: "fable")?.resetsAt ?? weekly?.resetAt
    }

    /// Fable'ın haftalık pencereden tahmini payı (sunucu değeri yokken).
    ///
    /// Model bazlı gerçek kota yalnızca OAuth katmanında var, o da kapalı.
    /// Bu değer yerel token payından türetiliyor.
    ///
    /// Pay MUTLAKA mevcut haftalık pencereye göre hesaplanmalı. Tüm arşiv
    /// üzerinden hesaplandığında aylar önceki Fable kullanımı bu haftanın
    /// kotasına yansıyor ve sunucu "hiç kullanmadın" derken uygulama yüzde
    /// gösterir.
    private var fableEstimate: Double? {
        guard let activity, let weekly, let start = weekly.windowStart else { return nil }
        guard let share = activity.share(matching: "claude-fable", since: start) else { return nil }
        return share * weekly.usedPercent
    }

    /// Cüzdanın durumu (bkz. `WalletState.resolve`).
    var wallet: WalletState {
        .resolve(server: serverUsage?.wallet, balance: serverBalance, account: account, liveExtraUsage: latestExtraUsage)
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

        let samples = archive.recent(now: now)
        fiveHour = serverOnlyWindow(.fiveHour, server: serverUsage, samples: samples, now: now)
        weekly = serverOnlyWindow(.sevenDay, server: serverUsage, samples: samples, now: now)
        latestExtraUsage = serverUsage.wallet?.roundedUtilization
        // Tazelik sunucu okumasına bağlanıyor: yerel dosya yoksa onun yaşı da yok.
        freshness = Freshness(lastUpdate: lastServerFetch ?? now, now: now)
        loadError = fallbackError
    }


    /// Yerel örneklerden türetilen pencere; varsa sunucu değeriyle düzeltilir.
    private func derivedWindow(_ kind: WindowKind, samples: [QuotaSample], now: Date) -> WindowPresentation? {
        let server = serverUsage?.window(for: kind)
        return deriver.derive(kind, from: samples, now: now).map { state in
            WindowPresentation.make(
                state: state,
                projection: projector.project(state.corrected(by: server), now: now),
                samples: samples,
                now: now,
                server: server
            )
        }
    }

    /// Yalnızca sunucu değerinden kurulan pencere. Sıfırlanma anı yoksa pencere yok.
    private func serverOnlyWindow(_ kind: WindowKind, server: ServerUsage, samples: [QuotaSample], now: Date) -> WindowPresentation? {
        server.window(for: kind).flatMap { window -> WindowPresentation? in
            guard let resetsAt = window.resetsAt else { return nil }
            let state = WindowState.fromServer(kind: kind, utilization: window.utilization, resetsAt: resetsAt)
            return WindowPresentation.make(
                state: state,
                projection: projector.project(state, now: now),
                samples: samples,
                now: now,
                server: window
            )
        }
    }

    /// Sunucu ekrandaki sayıların kaynağıysa, tazelik son sunucu okumasının yaşı.
    /// Kaynak sunucu değilse nil dönüp yerel dosyanın yaşına bırakıyor.
    private func serverFreshness(now: Date) -> Freshness? {
        guard authState == .signedIn, serverUsage != nil, let fetched = lastServerFetch else {
            return nil
        }
        return Freshness(lastUpdate: fetched, now: now)
    }

    private func clearWindows() {
        fiveHour = nil
        weekly = nil
    }
}
