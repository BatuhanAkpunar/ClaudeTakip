# ClaudeTakip: claude.ai Web Girişi Uygulama Rehberi

Bu belge, ClaudeTakip'in "Giriş yap" akışını (WKWebView penceresi, `sessionKey`
yakalama, sunucudan kullanım ve cüzdan verisi çekme) uçtan uca nasıl kuracağımızı
anlatır. Kaynak: 20'den fazla açık kaynak deponun kod okuması, canlı claude.ai
bundle analizi ve bağımsız doğrulama turu.

**Belgeyi okuma kuralı:** her iddianın yanında güven etiketi vardır.

| Etiket | Anlamı |
|---|---|
| DOĞRULANDI | Kaynak kodda veya ölçümle birebir teyit edildi |
| ÇÜRÜTÜLDÜ | İlk araştırmada iddia edildi, doğrulama turunda yanlış çıktı |
| DOĞRULANMADI | Tek kaynağa dayanıyor veya hiç test edilmedi. Kod yazmadan önce kendin ölç |

Mevcut kod tabanındaki ilgili dosyalar:

- `/Users/batuhanakpunar/claude-limits/App/Auth/LoginWindowController.swift`
- `/Users/batuhanakpunar/claude-limits/Sources/LimitCore/ClaudeWebClient.swift`
- `/Users/batuhanakpunar/claude-limits/Sources/LimitCore/SessionStore.swift`

---

## 1. Ekosistem tablosu

macOS menü çubuğu + claude.ai kullanım takibi alanında dört ayrı kimlik
doğrulama mimarisi var. "Uygulama içinden giriş" isteyen tek gerçek yol gömülü
WKWebView + `sessionKey` çerezi yakalamak.

### 1.1 Gömülü WKWebView ile giriş yapanlar (bizim desenimiz)

| Depo | Lisans | ★ | Google popup yönetimi | Çerez deposu | Saklama | Kopyalanabilir ne var |
|---|---|---|---|---|---|---|
| `matjam/headroom` | **MIT** | 1 | **Var**, gerçek NSWindow popup, WebKit'in verdiği `configuration` aynen kullanılıyor | `.default()` | bellek | **Kopyalamak için hukuken en güvenli örnek.** 153 satır, pencere başlığı literal "Sign in with Google", popup'a opener'ın UA'sı taşınıyor |
| `hamed-elfayome/Claude-Usage-Tracker` | **MIT** | 3309 | **Var**, gerçek NSPanel popup, verilen `configuration`. Yorum: "preserves window.opener linkage and shared cookies for Google SSO" | `.default()` | Keychain | `WKHTTPCookieStoreObserver` ile olay tabanlı yakalama, `SessionKeyValidator`, en eksiksiz Swift `Codable` şema seti (`ClaudeAPIService+Types.swift`) |
| `dowoonlee/ai-service-usage` | **LİSANSSIZ** | 6 | **Var**, en açıklayıcı gerçekleme. Popup yeniden kullanımı, `webViewDidClose` ile erken tetikleme | `.nonPersistent()` | Keychain | **Kod kopyalanamaz, yalnızca gerekçe referansı.** Frame seviyeli navigasyon politikası (hCaptcha tuzağı), `#77` çerez deposu hizalama regresyonu |
| `f-is-h/Usage4Claude` | **MIT** | 366 | Var ama popup'ı ana webview'a çökertiyor (`webView.load(...); return nil`) | `.nonPersistent()` | Keychain | Alan adı beyaz listesi, tam cookie header birleştirme, `transferCookiesToDefaultStore`. **Bu yolu terk etti**, sistem tarayıcısı OAuth'una geçti (Issue #49) |
| `prime-radiant-inc/agentic-usage-meter` | **MIT** | 28 | **Var**, NSPanel popup, verilen `configuration` | profil başına ayrı store | - | Hesap başına ayrı `WKWebsiteDataStore` (çoklu hesap için `nonPersistent` hilesinden temiz), `closePopup()` çift popup savunması |
| `theDanButuc/Claude-Usage-Monitor` | **MIT** | 52 | **YOK.** `WKUIDelegate` hiç uygulanmamış, Google butonu sessizce ölür | `.default()` | bellek | `/settings/usage`'a yükleyip yönlendirmeye güvenme deseni. Çerez filtresinde domain filtresi bilinçli yok (`.claude.ai` vs `claude.ai`) |
| `TheMarco/claude-usage` | **LİSANSSIZ** | 8 | Var ama ana webview'a çökertiyor | `.default()` | - | `checkExistingCookie`: zaten girişliyse pencereyi hiç gösterme. UX olarak kopyalanmaya değer |
| `AstroQore/vibe-bar` | **AGPL-3.0** | 16 | Var ama **kendi** `configuration`'ını üretiyor (çelişki, bkz. 2.3) | kendi kalıcı store | Keychain | **Kapalı kaynakta kullanılamaz.** Beyaz liste dışı popup'ı sistem tarayıcısına atma (phishing savunması), passkey için ayrı "tarayıcıda aç" düğmesi |
| `TadelUnso/claude-usage-widget` | **MIT** | 8 | Doğrulanamadı | `.default()` | UserDefaults (yalnız org id) | **`WebPageJSONFetcher`**: API URL'ine WebView ile navigate edip `document.body.innerText` okuma. Header taklidi gerektirmez |
| `clauding-lab/clauge` (Tauri/Rust) | **MIT** | 1 | Doğrulanamadı | Tauri webview | Keychain | Negatif URL kuralı: "claude.ai üzerinde login olmayan herhangi bir sayfa" |

### 1.2 Giriş yapmayanlar (referans değeri sınırlı ama uç nokta kaynağı)

| Depo | Lisans | ★ | Yöntem | Kopyalanabilir ne var |
|---|---|---|---|---|
| `steipete/CodexBar` | **MIT** | 20479 | Tarayıcı çerezini otomatik import veya elle yapıştırma | **Uç nokta yüzeyi için tek en iyi kaynak.** `ClaudeWebAPIFetcher.swift` (1460 satır), `ClaudeWebSessionKeyRenewalTracker` (Set-Cookie rotasyonu), alias listesi, `docs/claude.md` |
| `robinebers/openusage` | **MIT** | 3862 | Resmî Claude Desktop'ın Keychain kaydını okuyor (`service="Claude Safe Storage"`, `account="Claude Key"`) | Durum makinesi: `available/stale/notFound/invalid/permissionRequired`. İzin reddi ile token yokluğunu ayırmak kritik |
| `joshuadavidthomas/vibeusage` (Go) | **MIT** | 9 | Dosyadan `sessionKey`, düz `net/http` | **En eksiksiz tek dosya şema:** `response.go`. Bilinmeyen `seven_day_*` anahtarlarını `AdditionalPeriods` map'ine toplayan `UnmarshalJSON` |
| `niederme/ai-quota` | NOASSERTION | 8 | Gömülü WKWebView | Kod değil **karar dokümanı**: kurumsal Google hesabının UA override ile başarısız olduğunun test kaydı |
| `mgefimov/claude-legacy-ios` | **LİSANSSIZ** | 31 | Sadece e-posta magic link | **Ders:** Google butonunu CSS ile gizlemişler (`commit cf9bf2d`, "hide google button"). Çözemeyince kaldırmışlar |
| `tddworks/ClaudeBar` | LİSANSSIZ | 1431 | Yerel JSONL okuyor, claude.ai'ye hiç girmiyor | Yüksek yıldızına rağmen bizim desen için **uygun değil** |

**Lisans kararı:** kopyalanacak kod `matjam/headroom` (MIT, en kısa doğru Google
popup) ve `hamed-elfayome/Claude-Usage-Tracker` (MIT, şemalar) olmalı.
`dowoonlee/ai-service-usage` ve `AstroQore/vibe-bar` yalnızca **fikir** kaynağı:
biri lisanssız, diğeri AGPL.

---

## 2. Google ile girişin çalışan reçetesi

### 2.0 Önce: claude.ai'nin Google butonu gerçekten popup mu açıyor?

**DOĞRULANDI (canlı bundle, 2026-08-23).** claude.ai/login sayfası
`https://accounts.google.com/gsi/client` script'ini `<body>`'ye enjekte ediyor ve
`@react-oauth/google` deseniyle `initCodeClient` çağırıyor. `ux_mode` parametresi
**hiç verilmiyor**, yani Google Identity Services varsayılanı olan `popup` devreye
giriyor. Kesin kanıt: hata işleyicide `"popup_closed" === e.type` kontrolü var, bu
olay tipi yalnızca popup akışında üretilir.

Sonuç: `WKUIDelegate.createWebViewWith` olmadan Google butonu **sessizce hiçbir
şey yapmaz**. Hata da çıkmaz, konsol da boş kalır.

### 2.1 Adım 1: WebView konfigürasyonu

```swift
import AppKit
import WebKit

@MainActor
func makeLoginConfiguration() -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()

    // Boş depo: hiçbir OAuth sağlayıcısında hazır oturum olmasın. Google aksi
    // halde auto-SSO yapıp kullanıcıya hesap seçtirmiyor. Çerezi zaten kendimiz
    // saklıyoruz, bu deponun diske yazmasına gerek yok.
    configuration.websiteDataStore = .nonPersistent()

    // WKWebView'in varsayılan UA'sinda "Version/x.y" ve "Safari/605.1.15"
    // tokenlari YOK. applicationNameForUserAgent bunlari sona ekler ve sonuc
    // gercek Safari UA'si ile bayt bayt ayni olur.
    //
    // ZORUNLU SIRA: bu ozellik WKWebView olusturulmadan ONCE config uzerine
    // yazilmali. Webview yaratildiktan sonra config'e yazmak etkisizdir.
    configuration.applicationNameForUserAgent = "Version/17.6 Safari/605.1.15"

    return configuration
}
```

**Neden `applicationNameForUserAgent`, `customUserAgent` değil?**

İlk araştırma "applicationNameForUserAgent işe yaramaz, tam değiştirme gerekir"
diyordu. Bu **ÇÜRÜTÜLDÜ**: bu Mac'te ölçüldü, `applicationNameForUserAgent`
webview'dan önce set edildiğinde `navigator.userAgent` tam olarak
`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15`
oldu. `customUserAgent` de çalışır ama platform ve WebKit sürümünü elle sabitlemek
zorunda kalırsın, yani sistem güncellendiğinde string eskir. Ayrıca iOS 26.4'te
`customUserAgent`'a ASCII dışı karakter konulunca UA tamamen bozuluyor (Apple
forum thread/822080, DTS onayladı). `applicationNameForUserAgent` bu tuzağa
girmiyor.

**`javaScriptCanOpenWindowsAutomatically = true` gerekli mi? HAYIR.**

Bu ilk araştırmada "gerekli olabilir" diye geçmişti, **ÇÜRÜTÜLDÜ**: macOS'ta bu
özelliğin varsayılan değeri zaten `true` (Apple dokümantasyonu: "The default value
is false in iOS and true in macOS"). Ölçümle de teyit edildi: bayrak `false` iken
bile kullanıcı jesti olmadan çağrılan `window.open` `createWebViewWith`'i
tetikledi. macOS uygulamasında bu satır no-op. Yazma.

### 2.2 Adım 2: Navigasyon politikası (frame seviyeli)

Beyaz listeyi **tüm frame'lere** uygularsan claude.ai giriş sayfasının yüklediği
görünmez hCaptcha iframe'i (`newassets.hcaptcha.com`) listede olmadığı için
sessizce ölür ve o iframe URL'i yanlışlıkla kullanıcının harici tarayıcısında
açılır. `dowoonlee` bunu gerçek bir hata olarak yaşamış (DOĞRULANDI, kod yorumu).

```swift
enum LoginNavigationDecision: Sendable, Equatable {
    case allow
    case cancel
    case openExternally
}

/// Test edilebilir saf fonksiyon. Politikayi delegeden ayirmanin sebebi:
/// frame ayrimini birim testle sabitlemek.
enum LoginNavigationPolicy {
    /// Giris akisinda WebView icinde kalmasina izin verilen host'lar.
    ///
    /// Bu liste YALNIZCA en ust frame'e uygulanir. Alt frame'lere de uygularsan
    /// giris sayfasinin yukledigi ucuncu taraf kaynaklar (hCaptcha, Turnstile)
    /// sessizce olur.
    static let allowedHostSuffixes = [
        "claude.ai",
        "anthropic.com",
        "google.com",
        "gstatic.com",
        "googleusercontent.com",
        "googleapis.com",
        "apple.com",
        "icloud.com",
        "appleid.apple.com",
        "github.com",
        "workos.com",
        "auth0.com",
        "login.microsoftonline.com",
        "challenges.cloudflare.com",
        "hcaptcha.com",
    ]

    static func isAllowedHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return allowedHostSuffixes.contains { lowered == $0 || lowered.hasSuffix(".\($0)") }
    }

    /// - Parameter isMainFrame: en ust frame ise true. iframe ise false.
    ///   Popup (`targetFrame == nil`) burada gecirilir, `createWebViewWith`
    ///   yeniden degerlendirir.
    static func decide(for url: URL, isMainFrame: Bool) -> LoginNavigationDecision {
        if url.scheme == "about" { return .allow }
        guard url.scheme == "https", let host = url.host, !host.isEmpty else {
            return .cancel
        }
        // Alt frame kullaniciyi baska yere goturen bir gezinme degil.
        // Harici tarayiciya atmak yanlis olur.
        guard isMainFrame else { return .allow }
        return isAllowedHost(host) ? .allow : .openExternally
    }
}
```

Delege tarafı:

```swift
extension LoginWindowController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // targetFrame == nil ise bu bir popup istegi: gecir, createWebViewWith karar versin.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch LoginNavigationPolicy.decide(for: url, isMainFrame: isMainFrame) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .openExternally:
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        checkForSession()
    }
}
```

### 2.3 Adım 3: Popup yönetimi (en kritik kod)

Üç strateji sahada kullanılıyor ve depolar **çelişiyor**:

| Strateji | Kim uyguluyor | Değerlendirme |
|---|---|---|
| **A. Gerçek popup, WebKit'in verdiği `configuration`** | headroom, hamed-elfayome, dowoonlee, prime-radiant | **Bunu kullan.** İki bağımsız depo aynı gerekçeyi yazmış: verilen configuration `window.opener` bağını ve paylaşılan çerez deposunu korur |
| B. Popup'ı ana webview'a çökert (`webView.load(...); return nil`) | Usage4Claude, TheMarco, **ClaudeTakip'in şu anki kodu** | `window.opener` kopar. GIS'in `postMessage` ile opener'a kod döndürmesi tamamlanmaz |
| C. Gerçek popup ama **kendi** configuration | vibe-bar | Popup farklı çerez deposu kullanır, polling giriş çerezini göremez. Ayrıca opener kopar |

> **ClaudeTakip'te düzeltilecek:** `App/Auth/LoginWindowController.swift:143`
> şu anda B stratejisinde. A'ya geçmeli.

Hiçbir depoda üç stratejinin karşılaştırmalı testi yok (DOĞRULANMADI). Ama A'nın
iki bağımsız gerekçesi var, B ve C'nin sıfır gerekçesi var. A'yı seç.

```swift
extension LoginWindowController: WKUIDelegate {
    /// `window.open()` istegini karsilar.
    ///
    /// claude.ai'nin "Continue with Google" dugmesi Google Identity Services
    /// SDK'sidir ve `ux_mode` verilmediginden accounts.google.com'u POPUP olarak
    /// acar. Bu delege yoksa `window.open()` sessizce iptal edilir: ne pencere
    /// ne hata cikar, dugme olu gorunur.
    ///
    /// GELEN `configuration` AYNEN KULLANILMALI, yenisi uretilmemeli. WebKit
    /// opener ile ayni veri deposunu ve process pool'u bu nesne uzerinden
    /// devrediyor. Yeni configuration uretirsen:
    ///   1. Popup farkli cerez deposu kullanir, cerez yoklamamiz giris cerezini
    ///      hic gormez.
    ///   2. `window.opener` kopar ve GIS'in opener'a `postMessage` ile kod
    ///      dondurmesi tamamlanmaz.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        // Popup da kullaniciyi baska yere goturen bir gezinme: en ust frame ile
        // ayni olcute tabi tut.
        guard LoginNavigationPolicy.decide(for: url, isMainFrame: true) == .allow else {
            NSWorkspace.shared.open(url)
            return nil
        }

        // Cift tik savunmasi: acik popup varsa onu yeniden kullan.
        if let existing = popupWebView {
            existing.load(navigationAction.request)
            popupWindow?.makeKeyAndOrderFront(nil)
            return existing
        }

        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 640),
                              configuration: configuration)
        // Popup icinde ikinci bir window.open olabilir, delegeleri tasi.
        popup.navigationDelegate = self
        popup.uiDelegate = self
        // UA'yi ayrica set etmeye gerek YOK: applicationNameForUserAgent
        // configuration uzerinde, popup da ayni configuration'i kullaniyor.
        // `customUserAgent` yolunu secersen burada elle tasiman gerekir:
        //   popup.customUserAgent = webView.customUserAgent

        let window = NSWindow(
            contentRect: popup.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Giriş"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)

        popupWindow = window
        popupWebView = popup

        // WebKit istegi DONEN webview'e kendisi yukler. Burada load() cagirmak
        // cift yukleme yapar.
        return popup
    }

    /// Popup `window.close()` cagirdiginda, yani OAuth bittiginde tetiklenir.
    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        closePopup()
        // Popup kapanirken claude.ai cerezi zaten depoya girmis oluyor.
        // 1 saniyelik yoklamayi beklemeden hemen kontrol et.
        checkForSession()
    }

    func closePopup() {
        popupWindow?.delegate = nil
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }
}
```

Sınıfa eklenecek alanlar:

```swift
private var popupWindow: NSWindow?
private var popupWebView: WKWebView?
```

**Emniyet ağı:** `webViewDidClose` yalnızca DOM `window.close()` çağrıldığında
tetiklenir. Kullanıcı OAuth'u iptal edip pencereyi elle kapatırsa tetiklenmez.
Bu yüzden `NSWindowDelegate.windowWillClose` içinde de `closePopup()` çağır ve
1 saniyelik yoklama timer'ını bırak.

### 2.4 Adım 4: Çerez arama

**Kritik kural (DOĞRULANDI, gerçek regresyon):** WebView `nonPersistent` depoyla
giriş yapıyorsa çerez **aynı depodan** sorgulanmalı. `WKWebsiteDataStore.default()`
kalıcı depodur ve `nonPersistent` giriş çerezini içermez. `dowoonlee` bunu `#77`
regresyonu olarak yaşadı: sadece WebView'i `nonPersistent`'a çevirmişler, sorgu
deposunu hizalamamışlar, `sessionKey` yakalama sonsuza dek başarısız olmuş.

Popup opener'ın `configuration`'ını miras aldığı için **tek sorgu ikisini de
kapsar**. A stratejisini seçmenin ikinci faydası budur.

```swift
private func checkForSession() {
    guard let webView else { return }
    // Depo hizalamasi: `webView.configuration.websiteDataStore`, `.default()` DEGIL.
    let store = webView.configuration.websiteDataStore.httpCookieStore
    store.getAllCookies { [weak self] cookies in
        guard let self else { return }
        guard let cookie = cookies.first(where: {
            $0.name == "sessionKey"
                && Self.isClaudeDomain($0.domain)
                && !$0.value.isEmpty
        }) else { return }
        // Cikis yapildiginda cerez kisa/bos bir degerle yeniden yazilabiliyor.
        guard cookie.value.count > 20 else { return }
        Task { @MainActor in self.finish(with: cookie.value) }
    }
}

/// Cerez domain'i `.claude.ai` ve `claude.ai` arasinda degisiyor.
private static func isClaudeDomain(_ domain: String) -> Bool {
    let normalized = domain.lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return normalized == "claude.ai" || normalized.hasSuffix(".claude.ai")
}

private var captured = false

@MainActor
private func finish(with sessionKey: String) {
    guard !captured else { return }   // cift tetikleme savunmasi
    captured = true
    pollTimer?.invalidate()
    pollTimer = nil
    closePopup()
    onSuccess(sessionKey)
    close()
}
```

### 2.5 Adım 5: Giriş bittiğini anlama

Dört tetikleyiciyi birlikte kullan, hiçbiri tek başına yeterli değil:

| Tetikleyici | Ne yakalar |
|---|---|
| `didFinish` | Normal sayfa yüklemesi |
| `didReceiveServerRedirectForProvisionalNavigation` | Çerez yazılıp sayfa yüklenmeden önceki an |
| `webViewDidClose` | Popup `window.close()` çağırdığında, yani OAuth bittiğinde |
| 1 saniyelik `Timer` | Diğer üçünün kaçırdığı her şey |

**URL deseni kullanacaksan negatif kural kullan.** Giriş sonrası URL `/`, `/new`,
`/chats`, `/chat/<id>`, `/projects`, `/settings` arasında değişiyor. Pozitif
listeleme vaka kaçırır. Doğru kural: "claude.ai üzerinde `/login`, `/oauth/`,
`/auth/` ile başlamayan herhangi bir sayfa" (`clauding-lab/clauge` deseni).

### 2.6 Google girişinin BİLİNMEYEN kısmı

**DOĞRULANMADI, en önemli açık soru:** Beş depo Google popup'ı için kod yazmış
ve `dowoonlee` "delege ekleyince düğme çalışmaya başladı" diyor. Ama **hiçbirinde
"kişisel Google hesabıyla giriş baştan sona tamamlandı" diyen açık bir test kaydı
yok.**

Aksi yönde üç kanıt var:

1. **Kurumsal (Workspace) Google hesapları çalışmıyor (DOĞRULANDI).**
   `niederme/ai-quota` Safari UA override'ını `codex/test-corporate-oauth-ua`
   dalında v1.9.15 build 371 ile test etmiş. Sonuç birebir: "failed for the
   affected corporate Claude Google account." Google'ın klasik "This browser or
   app may not be secure" engeli **çıkmamış**, Google hesap ekranına ulaşılmış,
   Claude'a dönüşte "There was an error logging you in" alınmış. Belgenin
   tavsiyesi: "Stop layering WebView bypasses for Claude corporate Google login."

2. **Usage4Claude bu yolu terk etti (DOĞRULANDI).** Issue #49 başlığı: "Not able
   to connect with claude.ai via Google", durumu closed. Çözüm gömülü webview'ı
   düzeltmek değil, sistem tarayıcısı OAuth'una geçmek olmuş.

3. **iOS'ta `window.opener` null (DOĞRULANDI, macOS'ta DOĞRULANMADI).** Apple
   forum thread/759487 ve thread/810417: iOS 17.5+ WKWebView popup'ında
   `window.opener` null dönüyor, Apple DTS mühendisi "by design due to WKWebView
   isolation" demiş ve çözüm verememiş. **macOS'ta aynı regresyonun olup olmadığı
   test edilmedi.** Varsa GIS popup akışı UA ne olursa olsun tamamlanamaz.

**Ne yapmalı:** Google akışını yaz (30 dakika), sonra **kendi kişisel Gmail
hesabınla uçtan uca test et.** Bu tek deneme, kalan tek belirleyici bilinmeyeni
kapatır. Çalışmıyorsa 2.7'deki yedeklere geç.

### 2.7 Google çalışmazsa: yedek yollar

Öncelik sırasıyla:

1. **E-posta magic link.** WKWebView'de kesin çalışır, popup yok, üçüncü taraf
   yok. **Tuzak (DOĞRULANDI, Anthropic destek belgesi):** link 15 dakika
   geçerli, ve linki talep ettiğin cihazdan **farklı** bir cihazda açarsan
   doğrudan giriş yapmaz, bir doğrulama kodu üretir ve o kodu **orijinal
   cihaza** girmen gerekir. Kullanıcı postayı telefonundan açarsa bu ikinci akış
   devreye girer, giriş penceresinin kod yapıştırmayı desteklemesi gerekir.

2. **"Continue with Apple".** claude.ai'de `login-with-apple` kod yolu var ve
   **AppleID JS SDK'sı yüklenmiyor, `window.open` ve `postMessage` bundle'da sıfır
   kez geçiyor** (DOĞRULANDI, bundle analizi). Yani tam sayfa yönlendirme.
   **AMA:** buton `claudeai_web_enable_apple_login` bayrağına bağlı ve
   2026-08-23'te İstanbul'dan canlı sayfada **hiç render edilmiyor**. Ayrıca
   "popup yok, o hâlde WKWebView'de çalışır" çıkarımı **ÇÜRÜTÜLDÜ**: Apple forum
   thread/740376 başlığı birebir "iOS 17.1 breaks Sign-In with Apple (JavaScript)
   within WKWebView". macOS için test kaydı yok.

3. **Kullanıcıyı sistem tarayıcısına atıp çerezi elle aldırma.** `vibe-bar`
   deseni: ayrı "Tarayıcıda aç" düğmesi + kullanıcı Safari'de giriş yapar +
   `WKWebsiteDataStore.default()` üzerinden çerezi içeri aktarma. Kırılgan ve UX
   kötü, son çare.

4. **Google butonunu gizle** (`mgefimov/claude-legacy-ios` deseni). Kabullenme.
   Yapma, önce 1'i düzgün kur.

### 2.8 ASWebAuthenticationSession neden uymuyor

**DOĞRULANDI, `niederme/ai-quota` spec'i.** İki sebep:

1. claude.ai giriş sonunda `claudetakip://` gibi bir şemaya **yönlendirmiyor**.
   Sadece `https://claude.ai/`'ye iniyor ve çerez set ediyor. Callback şeması
   olmadan `ASWebAuthenticationSession` tamamlanamaz.
2. Oturum bizim process'imizin dışında çalışıyor. Çerezler bizim
   `WKWebsiteDataStore`'umuza değil, tarayıcı/auth-session deposuna düşüyor.

Ayrıca ilk araştırmanın "UIApplication.open yerine ASWebAuthenticationSession
kullanın, yoksa App Store reddi alırsınız" tavsiyesi **ÇÜRÜTÜLDÜ**: alıntılanan
Apple forum thread/750400'de reddedilen macOS uygulamaları **zaten**
`ASWebAuthenticationSession` kullanıyordu ve tam da varsayılan tarayıcı açıldığı
için reddedildiler. Zaten DMG ile dağıtacağız, App Review yok.

---

## 3. claude.ai iç API haritası

Tüm uçlar `sessionKey` çerezi ile çağrılır. Şemalar `steipete/CodexBar`
(`ClaudeWebAPIFetcher.swift`), `hamed-elfayome/Claude-Usage-Tracker`
(`ClaudeAPIService+Types.swift`) ve `joshuadavidthomas/vibeusage`
(`response.go`) kod okumasıyla DOĞRULANDI.

### 3.1 Uç nokta özeti

| Uç nokta | Ne verir | ClaudeTakip'te gerekli mi |
|---|---|---|
| `GET /api/organizations` | Org listesi, `uuid` kaynağı | **Evet** |
| `GET /api/organizations/{id}/usage` | Kullanım pencereleri + `extra_usage` | **Evet, ana uç** |
| `GET /api/organizations/{id}/overage_spend_limit` | Ek kullanım tavanı | Evet (cüzdan) |
| `GET /api/organizations/{id}/overage_credit_grant` | Kalan hibe kredisi | Opsiyonel |
| `GET /api/organizations/{id}/prepaid/credits` | Ön ödemeli bakiye | Opsiyonel |
| `GET /api/account` | E-posta, plan (`rate_limit_tier`) | Evet (popover başlığı) |
| `GET /api/auth/current_account` | org uuid yedeği | Yedek |
| `GET /api/bootstrap` | org uuid yedeği | Yedek |
| `GET /v1/code/routines/run-budget` | Routines bütçesi (Team) | Hayır, atla |

### 3.2 `GET /api/organizations`

**İstek:**

```
GET https://claude.ai/api/organizations
Cookie: sessionKey=sk-ant-sid02-...
Accept: application/json
```

**Yanıt (dizi):**

```json
[
  {
    "uuid": "00000000-0000-4000-8000-000000000002",
    "id": "00000000-0000-4000-8000-000000000002",
    "name": "Example Organization",
    "capabilities": ["chat", "claude_pro"]
  }
]
```

**Org seçim mantığı (DOĞRULANDI, CodexBar):** listeden ilk elemanı almak yanlış.
Doğru sıra:

1. `capabilities` içinde `"chat"` olan ilk org
2. yoksa `capabilities == ["api"]` **olmayan** ilk org (API-only org'ları ele)
3. yoksa ilk eleman

```swift
func selectOrganization(from list: [[String: Any]]) -> String? {
    func caps(_ item: [String: Any]) -> [String] {
        item["capabilities"] as? [String] ?? []
    }
    if let chat = list.first(where: { caps($0).contains("chat") }) {
        return chat["uuid"] as? String
    }
    if let nonAPI = list.first(where: { caps($0) != ["api"] }) {
        return nonAPI["uuid"] as? String
    }
    return list.first?["uuid"] as? String
}
```

> **ClaudeTakip'te düzeltilecek:** `ClaudeWebClient.organizationID()`
> (`Sources/LimitCore/ClaudeWebClient.swift:38`) şu anda `list.first` alıyor.

**Bedava optimizasyon (DOĞRULANDI):** org uuid'si `lastActiveOrg` çerezinde de
duruyor ve ömrü 1 yıl. Giriş penceresinde `sessionKey` ile birlikte onu da
yakalarsan bir HTTP isteği tasarruf edersin.

### 3.3 `GET /api/organizations/{id}/usage` (ana uç)

Aynı veri **iki kez** taşınıyor: üst seviye pencere nesneleri ve `limits[]` dizisi.

```json
{
  "five_hour":            { "utilization": 16.6, "resets_at": "2026-08-23T15:00:00.000000Z" },
  "seven_day":            { "utilization": 42.1, "resets_at": "2026-08-27T09:00:00.000000Z" },
  "seven_day_opus":       { "utilization": 8.0,  "resets_at": "2026-08-27T09:00:00.000000Z" },
  "seven_day_sonnet":     { "utilization": 31.4, "resets_at": "2026-08-27T09:00:00.000000Z" },
  "seven_day_oauth_apps": { "utilization": 0.0,  "resets_at": "2026-08-27T09:00:00.000000Z" },
  "seven_day_cowork":     null,
  "seven_day_routines":   { "utilization": 14.0, "resets_at": "2026-08-27T09:00:00.000000Z" },
  "seven_day_omelette":   { "utilization": 42.1, "resets_at": "2026-08-27T09:00:00.000000Z" },
  "seven_day_design":     null,
  "omelette_promotional": null,

  "extra_usage": {
    "is_enabled":    true,
    "monthly_limit": 2050,
    "used_credits":  347,
    "utilization":   16.9,
    "currency":      "USD"
  },

  "limits": [
    {
      "kind":       "session",
      "group":      "five_hour",
      "percent":    17,
      "resets_at":  "2026-08-23T15:00:00.000000Z",
      "is_active":  true,
      "scope":      { "model": null, "surface": null }
    },
    {
      "kind":       "weekly_scoped",
      "group":      "seven_day_opus",
      "percent":    8,
      "resets_at":  "2026-08-27T09:00:00.000000Z",
      "is_active":  true,
      "scope":      { "model": { "id": "claude-opus-4-6", "display_name": "Opus" }, "surface": null }
    }
  ]
}
```

**Ayrıştırma kuralları:**

| Kural | Gerekçe |
|---|---|
| `utilization` **float**, `percent` **int**. İkisini de `round()` et | Aynı pencere için `16.6` ve `17` gelir, yuvarlamazsan 1 puan sapma gösterirsin |
| `five_hour` **null** olabilir | Kurumsal ve kredi tabanlı hesaplarda null döner. **Hata sayma**, 0% olarak ele al (DOĞRULANDI, CodexBar kod yorumu) |
| `seven_day_omelette` ve `seven_day_design` **YOK SAY** | Claude Design ana Claude kullanım limitiyle **aynı havuzu** paylaşıyor. Ayrı gösterirsen kullanıcıya aynı kotayı iki kez göstermiş olursun (DOĞRULANDI, CodexBar `docs/claude.md:83`) |
| `seven_day_cowork` ve `seven_day_routines` **alias**, ikisi aynı pencere | Dolu olanı seç: `routines: null` + `cowork: 14` ise 14 kullan |
| Bilinmeyen `seven_day_*` anahtarlarını topla | Şema büyüyor. `vibeusage` bunları `AdditionalPeriods` map'ine atıyor, ileriye dönük en sağlam desen |

> **ClaudeTakip'te düzeltilecek:** `ServerUsage.init` (`ClaudeWebClient.swift:172`)
> `seven_day_omelette`'i "Fable" adıyla ayrı bir model penceresi olarak
> gösteriyor. Bu ana `seven_day` ile aynı havuz, kaldırılmalı.

### 3.4 `extra_usage` (cüzdan, en çok yanlış anlaşılan alan)

```json
"extra_usage": {
  "is_enabled":    true,
  "monthly_limit": 2050,
  "used_credits":  347,
  "utilization":   16.9,
  "currency":      "USD"
}
```

| Alan | Tip | Not |
|---|---|---|
| `is_enabled` | bool | `false` ise **hiçbir değeri gösterme**, kullanıcı ek kullanımı açmamış |
| `monthly_limit` | number | **SENT cinsinden.** `2050` = 20,50 USD. `0` veya `null` ise "limitsiz" |
| `used_credits` | number | **SENT cinsinden.** `347` = 3,47 USD |
| `utilization` | float | Tavanın yüzdesi. 100'ü aşabilir |
| `currency` | string | `"USD"` |
| `resets_at` | **YOK** | Bu alan gelmiyor. Sıfırlama tarihini kendin hesapla: **ayın 1'i, UTC** (DOĞRULANDI, `ShuheiKonno/ClaudeMonitor` kod yorumu) |

**Ad tuzağı:** `extra_usage` içinde alan adı `monthly_limit`. `overage_spend_limit`
ucunda **aynı kavramın** adı `monthly_credit_limit`. CodexBar ikisini de deniyor.

> **ClaudeTakip'te düzeltilecek:** `ServerUsage.Wallet` (`ClaudeWebClient.swift:149`)
> `monthlyLimit`'i "para birimi cinsinden" diye belgeliyor. Sent cinsinden, 100'e
> bölünmeli. `resets_at` de hiç ele alınmamış.

### 3.5 Cüzdan yan uçları

```
GET /api/organizations/{id}/overage_spend_limit
{ "monthly_credit_limit": 2050, "currency": "USD", "used_credits": 347, "is_enabled": true }

GET /api/organizations/{id}/overage_credit_grant
{ "remaining_balance": 500, "currency": "USD", "total_granted": 1000 }

GET /api/organizations/{id}/prepaid/credits
{ "amount": 1500, "currency": "USD", "auto_reload_settings": null, "pending_invoice_amount_cents": null }
```

`auto_reload_settings` null ise otomatik yükleme kapalı.

Bu üç uç **best-effort** olmalı: kısa timeout ver, hata gelirse ana kullanım
verisini bloklamadan `nil` geç. CodexBar bunun için `BoundedTaskJoin` kullanıyor.

### 3.6 `GET /api/account`

```json
{
  "email_address": "you@example.com",
  "memberships": [
    {
      "organization": {
        "uuid": "00000000-...",
        "name": "Example Organization",
        "rate_limit_tier": "default_claude_max_5x",
        "billing_type": "stripe"
      },
      "seat_tier": "standard"
    }
  ]
}
```

Plan etiketi `rate_limit_tier`'dan çıkarılıyor: `default_claude_max_5x` -> "Max 5x",
`default_claude_max_20x` -> "Max 20x". Alternatif: `/api/organizations`
yanıtındaki `capabilities`'in son elemanı, `claude_` ön eki atılarak
(`claude_pro` -> "Pro"); tek eleman varsa "Free".

### 3.7 `GET /v1/code/routines/run-budget`

Team planlarında 200, Max/Pro bireysel planlarda 403/404 döner. **Bu normal**,
`nil`'e düşür ve devam et. İki başlık **zorunlu**:

```
anthropic-beta: ccr-triggers-2026-01-30
anthropic-version: 2023-06-01
```

Yanıt `{ "limit": "...", "used": "...", "unified_billing_enabled": bool }`.
`limit` ve `used` **string** olarak geliyor, sayıya çevir.

ClaudeTakip için gerekli değil, atla.

---

## 4. Cloudflare ve başlık gereksinimleri

### 4.1 Gerçekten sorun mu? Hayır, sanıldığı kadar değil

**DOĞRULANDI.** `steipete/CodexBar` (20.479 yıldız, aktif) claude.ai çağrılarında
**yalnızca iki başlık** set ediyor:

```
Cookie: sessionKey=...
Accept: application/json
```

`User-Agent` **hiç** set etmiyor. Aynı repoda Copilot/Devin/Codex sağlayıcıları
için `User-Agent` set ediliyor, yani bu bilinçli bir tercih. `vibeusage` (Go) düz
`net/http` ile, 30 saniye timeout, `User-Agent` yok. İkisi de sahada çalışıyor.

Yani `sec-fetch-*`, `anthropic-client-platform`, `origin`, `referer` başlıkları
**zorunlu değil**. Bunlar opsiyonel sertleştirme.

### 4.2 403'ün gerçek sebepleri

`guidodinello/claude-client` kök neden analizi (2026-08-19, DOĞRULANDI):

| Sebep | Belirti | Çözüm |
|---|---|---|
| **VPN çıkış IP itibarı** | Aynı token, aynı kod: VPN kapalı 200, VPN açık her seferinde 403 JS challenge | Kod tarafında çözüm yok. Kullanıcıya "VPN'i kapat" mesajı göster |
| **Cloudflare çerez uyuşmazlığı** | Tarayıcıdan tam `Cookie` header'ı kopyalayınca 403 | `cf_clearance`, `__cf_bm`, `_cfuvid` çerezlerini **gönderme**. Bunlar gerçek tarayıcı fingerprint'ine bağlı, farklı TLS yığınından gönderilince uyuşmazlık üretiyor |

**Karar: URLSession isteklerinde yalnızca `sessionKey` gönder.** Diğer çerezleri
strip et.

```swift
/// Cloudflare cerezleri gercek tarayici fingerprint'ine bagli. Farkli bir TLS
/// yiginindan gonderilirse uyusmazlik uretip 403'e sebep oluyorlar.
/// URLSession isteginde YALNIZCA sessionKey gonder.
private static let cloudflareCookieNames: Set<String> = [
    "cf_clearance", "__cf_bm", "_cfuvid",
]
```

### 4.3 ÇELİŞKİ: tam cookie header gerekli mi?

`f-is-h/Usage4Claude` **tam tersini** yapıyor: WebView'daki tüm çerezleri
(`cf_clearance`/`__cf_bm` dahil) `Cookie` header'ına birleştirip doğrulama
isteğine ekliyor. Kod yorumu: "Cloudflare geçiş belgesi eksikliğinden
engellenmesin."

**DOĞRULANMADI, çözülmedi.** İki depo zıt tavsiye veriyor ve karşılaştırmalı test
yok. Açıklama muhtemelen şu: Usage4Claude çerezleri WebView'dan **aynı makinede,
aynı anda** alıyor, dolayısıyla `cf_clearance` hâlâ taze. AIQuotaBar ise
tarayıcıdan **elle kopyalanmış** eski çerezleri strip ediyor.

**Karar:** `sessionKey`-only ile başla (CodexBar kanıtı en güçlü, 20k yıldız).
403 alırsan 4.5'teki teşhis akışını çalıştır, sonra tam header'ı dene.

### 4.4 User-Agent: WKWebView içinde ve dışında farklı kural

Bu ayrım kritik ve iki depo bunu zıt anlatıyor çünkü **farklı bağlamlardan**
bahsediyorlar:

| Bağlam | Doğru UA | Gerekçe |
|---|---|---|
| **WKWebView içinde** (giriş penceresi) | **Safari** | `TadelUnso` kod yorumu: "Cloudflare's Turnstile compares more than the UA string; claiming Chrome from WKWebView produces a fingerprint mismatch and an endless 'verify you are human' loop" |
| **URLSession'da** (API çağrıları) | Chrome veya hiç | JS motoru yok, fingerprint karşılaştırması yapılamaz. Chrome UA taklidi zararsız |

> **ClaudeTakip'te durum:** `ClaudeWebClient.safariUserAgent` giriş penceresinde,
> `chromeUserAgent` URLSession'da kullanılıyor. **Bu doğru.** Ama 4.1'e göre
> URLSession'da UA'ya hiç gerek yok. Basitleştirilebilir.

### 4.5 401 ile 403'ü ayır (önemli hata kaynağı)

**DOĞRULANDI, `claude-client`'ın shipped düzeltmesi.** 403 her zaman "token bitti"
demek **değil**. Kullanıcıya yanlışlıkla "yeniden giriş yap" dersen, Cloudflare
challenge'ı geçmeyeceği için sonsuz döngüye sokarsın.

Sınıflandırma sırası:

```swift
public enum ClientError: Error, Sendable, Equatable {
    case notAuthenticated
    /// Oturum dusmus, yeniden giris gerekiyor.
    case sessionExpired
    /// Cloudflare challenge. Cerez saglam, ag/IP sorunlu. YENIDEN GIRIS ISTEME.
    case cloudflareChallenge
    case badResponse(Int)
    case malformed(String)
    case transport(String)
}

/// 403'u dogru siniflandirir.
///
/// DIKKAT: claude.ai'nin KENDISI Cloudflare arkasinda sunuluyor, yani
/// `server: cloudflare` ve `cf-ray` basliklari MESRU uygulama yanitlarinda da
/// var. Sadece bunlara bakarak ayrim yapmak teshisi TERSINE cevirir.
func classifyForbidden(response: HTTPURLResponse, body: Data) -> ClientError {
    // 1. Once Cloudflare kaniti ara: `cf-mitigated` baslgi kesin isaret.
    if response.value(forHTTPHeaderField: "cf-mitigated") != nil {
        return .cloudflareChallenge
    }
    let contentType = (response.value(forHTTPHeaderField: "content-type") ?? "").lowercased()
    if contentType.contains("text/html") {
        // Uygulama katmani JSON doner. HTML = challenge sayfasi.
        return .cloudflareChallenge
    }

    // 2. Uygulama katmanini POZITIF dogrula: JSON govde = gercek yetki reddi.
    if contentType.contains("application/json"),
       (try? JSONSerialization.jsonObject(with: body)) != nil {
        return .sessionExpired
    }

    // 3. Hicbiri degilse token problemi oldugunu VARSAYMA.
    return .cloudflareChallenge
}
```

`401` koşulsuz `sessionExpired`. Cloudflare 401 ile challenge yapmaz.

> **ClaudeTakip'te düzeltilecek:** `ClaudeWebClient.get` (`ClaudeWebClient.swift:130`)
> `case 401, 403: throw ClientError.sessionExpired` diyor. 403 ayrılmalı.

### 4.6 Cloudflare'i tamamen atlatan iki desen (yedek plan)

Sık 403 alırsan mimariyi değiştirebilirsin:

1. **WebView içinden JSON okuma (`TadelUnso` deseni).** Gizli bir `WKWebView`'ı
   doğrudan API URL'ine navigate edip `document.body.innerText` okuyorsun. Tüm
   çerezleri ve gerçek tarayıcı fingerprint'ini otomatik miras alır, hiç header
   taklidi gerekmez.

```swift
private final class WebPageJSONFetcher: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Data, Error>?
    private var responseStatus: Int?

    init(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = "Version/17.6 Safari/605.1.15"
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                            configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func fetch(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url,
                                    cachePolicy: .reloadIgnoringLocalCacheData,
                                    timeoutInterval: 30))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        responseStatus = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body.innerText") { [weak self] value, error in
            guard let self, let continuation = self.continuation else { return }
            self.continuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else if let text = value as? String, let data = text.data(using: .utf8) {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: URLError(.cannotParseResponse))
            }
        }
    }
}
```

**Maliyet:** her sorguda WebView ayakta tutmak, RAM ve CPU. Menü çubuğu
uygulaması için ağır. Yedek olarak tut, varsayılan yapma.

2. **Tarayıcı sekmesinde XHR** (`xbar` eklentisi deseni): AppleScript ile açık
   Chrome sekmesinde JS çalıştırma. Kullanıcının tarayıcısını açık tutmasını
   gerektirir, ClaudeTakip için uygun değil.

### 4.7 Sorgulama sıklığı

| Proje | Aralık |
|---|---|
| Claude-Usage-Tracker | 30 sn |
| tamaclaude, claude-watch | 60 sn |
| ClaudeCap | 120 sn |
| ClaudeMonitor | 5 dk |
| claude-usage-meter | 10 dk alarm + 30 sn sert alt sınır |

**Karar: 60 saniye.** Yaygın, tolere edildiği kanıtlı, ve 5 saatlik pencere zaten
~3 dakikada 1 puan ilerlediği için daha sık sorgulamak hiçbir şey kazandırmıyor.
30 saniyenin altına inme. 429 gelirse `Retry-After` başlığını parse et.

---

## 5. Oturum yaşam döngüsü

### 5.1 Çerez ömürleri

**DOĞRULANMADI (tek blog kaynağı, `kukie.io`):**

| Çerez | Beyan edilen ömür |
|---|---|
| `sessionKey` | 1 ay |
| `lastActiveOrg` | 1 yıl |
| `activitySessionId` | 12 saat |
| `__cf_bm` | 30 dakika (her istekte yenilenir) |
| `cf_clearance` | 1 yıl |

**Uyarı:** "1 ay" bir `max-age` beyanı, **sunucu tarafı oturum geçerliliğinin
kanıtı değil.** Sunucu çerezi her an geçersizleştirebilir.

Sahadaki gerçek kadans daha kötü. `steipete/CodexBar` issue #1287 (2026-06-03)
başlığı birebir: "Claude session repeatedly shows 'Unauthorized. Your Claude
session may have expired.' — both Web and OAuth paths lack working refresh".
Gövdede verilen kadans: **bazı kullanıcılar için birkaç günde bir**, OAuth
kullanıcıları için **~8 saatte bir**.

> **Not:** İlk araştırma bu iddiayı `KeychainMigrationService.swift` ve
> `SessionKeyValidator.swift` dosyalarına dayandırıyordu. Bu **ÇÜRÜTÜLDÜ**: ilki
> tek seferlik bir depolama taşıması (dosya/UserDefaults -> Keychain), ikincisi
> bir format/XSS doğrulayıcısı. İkisi de oturum ömrüyle ilgisiz. Doğru kanıt
> yukarıdaki issue.

### 5.2 Anahtar formatı

**DOĞRULANDI.** Format Nisan 2026'da `sk-ant-sid01-*`'den `sk-ant-sid02-*`'ye
geçti (`ChatGPTBox-dev/chatGPTBox` PR #960, açılış 2026-04-11, merge 2026-05-21).

Sürüm numarasını **hardcode etme**:

```swift
/// Anahtar formati surumleniyor: sid01 -> sid02 gecisi Nisan 2026'da oldu.
/// Surum numarasini sabitleme, prefix kontrolu yeterli.
func looksLikeSessionKey(_ value: String) -> Bool {
    value.hasPrefix("sk-ant-sid") && value.count > 20
}
```

### 5.3 Anahtar kendiliğinden dönebilir (rolling renewal)

**DOĞRULANDI, testle sabitlenmiş (CodexBar `ClaudeWebCookieRenewalTests`).**
200 yanıtlarında `Set-Cookie` ile **yeni** bir `sessionKey` gelebiliyor ve eskisi
geçersizleşebiliyor. Bunu yok sayarsan oturum gereksiz yere düşer.

```swift
import Foundation

/// 200 yanitlarindaki `Set-Cookie` basliklarindan yenilenmis sessionKey'i yakalar.
///
/// claude.ai oturum anahtarini bazen dondurup eskisini gecersizlestiriyor.
/// Yeni degeri yok sayarsan bir sonraki istekte 401 alirsin.
/// Sadece statusCode == 200 iken bak: hata yanitlarindaki Set-Cookie cogu zaman
/// oturumu SIFIRLAMA amacli.
public struct SessionKeyRenewalTracker: Sendable {
    private static let pattern = #"(?i)(?:^|[,\r\n])\s*sessionKey=([^;,\r\n]+)"#

    public init() {}

    public func renewedKey(from response: HTTPURLResponse) -> String? {
        guard response.statusCode == 200 else { return nil }

        // Birden fazla Set-Cookie geldiginde Foundation bunlari tek bir string'de
        // virgulle birlestiriyor. Regex bu yuzden virgul sinirini de kabul ediyor.
        let raw = response.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        guard !raw.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(pattern: Self.pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: raw) else { return nil }

        let value = String(raw[valueRange])
        guard value.hasPrefix("sk-ant-") else { return nil }
        return value
    }
}
```

Kullanım: her 200 yanıtında kontrol et, yeni anahtar varsa **hem sonraki
isteklerde kullan hem de depoya geri yaz.**

### 5.4 Düşme tespiti

```
401                          -> sessionExpired, kesin
403 + cf-mitigated / HTML    -> cloudflareChallenge, yeniden giris ISTEME
403 + JSON gövde             -> sessionExpired
200 + Set-Cookie(sessionKey) -> anahtar dondu, guncelle
429                          -> Retry-After kadar bekle, oturum saglam
```

**Ek koruma:** çerezi kaydetmeden **önce** doğrula. Giriş penceresi kapanmadan
`/api/organizations` çağır; 200 dönerse kaydet, dönmezse pencereyi açık tut ve
kullanıcıya hatayı göster. Bu, yarım kalmış bir OAuth akışında boş/geçersiz çerez
kaydetmeyi engeller.

### 5.5 Yeniden giriş UX'i

Tasarım kararları:

| Durum | Menü çubuğu | Popover |
|---|---|---|
| Oturum sağlam | Normal yüzde | Normal |
| `cloudflareChallenge` | **Son bilinen değer + soluk** | "Bağlantı doğrulanamadı. VPN kullanıyorsan kapatıp tekrar dene." + "Tekrar dene" |
| `sessionExpired` | Nötr ikon, yüzde yok | "Oturumun sona erdi." + "Giriş yap" |
| Ağ yok | Son bilinen değer + soluk | "Çevrimdışı" |

Üç kural:

1. **`sessionExpired` gelir gelmez giriş penceresini otomatik açma.** Kullanıcı
   başka iş yaparken ekranına pencere fırlatmak saldırgan. Popover'da düğme
   göster, tıklayınca aç.
2. **`cloudflareChallenge`'ı asla "yeniden giriş yap" diye gösterme.** Kullanıcı
   girer, yine 403 alır, sonsuz döngü. Bu tam da `claude-client`'ın düzelttiği
   hata.
3. **Son bilinen değeri sakla ve zaman damgasıyla göster.** "42% (12 dk önce)"
   boş ekrandan iyidir.

Ayrıca `TheMarco/claude-usage`'ın `checkExistingCookie` deseni kopyalanmalı:
giriş penceresini açmadan önce depodaki çerezi test et, geçerliyse pencereyi hiç
gösterme.

### 5.6 Programatik yenileme yok

**DOĞRULANMADI ama hiçbir depoda aksi yok:** `sessionKey` için refresh token
mekanizması yok. Süresi dolduğunda kullanıcı yeniden giriş yapmak zorunda. Tek
"yenileme" 5.3'teki pasif rolling renewal.

---

## 6. Saklama kararı: Keychain

**Karar: Keychain. Dosya yolu yalnızca imzasız geliştirme derlemeleri için
geçici bir kaçış olarak kalsın.**

### 6.1 Mevcut durum ve gerekçenin değerlendirmesi

`Sources/LimitCore/SessionStore.swift` şu anda dosya kullanıyor ve gerekçesi
belgelenmiş: "geliştirme derlemeleri ad-hoc imzalı ve her derlemede imza
değişiyor, bu da Keychain erişim listesini bozup her açılışta izin penceresi
çıkarıyor."

Bu gerekçe **geliştirme aşaması için doğru**. Ama üründe geçersiz: 7. bölümde
Developer ID imzasına geçince imza **sabit** olur ve prompt kaybolur.

### 6.2 Sahadaki dağılım

| Saklama | Kimler |
|---|---|
| **Keychain** | dowoonlee, clauge, vibe-bar, CodexBar, hamed-elfayome, Usage4Claude, ClaudeCap |
| UserDefaults (yalnız org id) | TadelUnso |
| Bellek | theDanButuc |
| Dosya | (yok) |

Çoğunluk Keychain. Dosya kullanan tek örnek ClaudeTakip.

### 6.3 Neden Keychain

1. **`sessionKey` tam yetkili bir oturum anahtarı.** Kullanım verisi okumakla
   kalmaz, o çerezle claude.ai'de kullanıcının hesabına girilir: sohbet geçmişi,
   projeler, ayarlar. `0600` dosya izni, `~` altında çalışan **her** işlemden
   korumaz. Sandbox'sız bir CLI, bir npm postinstall script'i, bir Electron
   uygulaması o dosyayı okuyabilir. Keychain kaydına erişim ise imzaya bağlı.
2. **Yedeklere ve senkronizasyona sızmaz.** `Library/Application Support` Time
   Machine ve çoğu yedekleme aracı tarafından kopyalanır. Keychain öğesi
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` ile cihazdan çıkmaz.
3. **`nonPersistent` WebView tercihiyle tutarlı.** `dowoonlee`'nin gerekçesi:
   anahtar Keychain'e yazıldığı için `~/Library/WebKit` altında düz metin kopya
   bırakmamak. Ama Keychain yerine dosyaya yazarsan o argüman çöker, yine düz
   metin kopya bırakmış olursun.

### 6.4 Gerçekleme

```swift
import Foundation
import Security

/// Oturum anahtarini Keychain'de saklar.
///
/// `ThisDeviceOnly` bilincli: anahtar iCloud Keychain ile baska cihaza gitmemeli,
/// zaten o cihazda ayri bir oturum acilmali. `AfterFirstUnlock` menu cubugu
/// uygulamasi icin gerekli: giris ogesi olarak acilista calisiyoruz ve o anda
/// kullanici henuz ekrani kilitlememis olsa bile ilk kilit acilmis oluyor.
public struct KeychainSessionStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        /// Kullanici Keychain erisimini reddetti. "Anahtar yok" ile ayni sey DEGIL:
        /// kullaniciya "yeniden giris yap" demek yerine izin istemeliyiz.
        case accessDenied
        case unhandled(OSStatus)
    }

    private let service: String
    private let account: String

    public init(service: String = "com.claudetakip.session", account: String = "claude.ai") {
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

    public func save(_ sessionKey: String) throws {
        guard let data = sessionKey.data(using: .utf8) else { return }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(baseQuery as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw StoreError.accessDenied
        default:
            throw StoreError.unhandled(status)
        }
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw StoreError.accessDenied
        default:
            throw StoreError.unhandled(status)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
```

### 6.5 Durum makinesini ayır

`robinebers/openusage` bunu doğru yapıyor: **izin reddi ile anahtar yokluğunu
karıştırma.** Kullanıcıya "yeniden giriş yap" demek ile "Keychain erişimine izin
ver" demek tamamen farklı iki eylem.

```swift
public enum CredentialState: Sendable, Equatable {
    case available(String)
    case notFound            // hic giris yapilmamis -> "Giris yap"
    case permissionRequired  // Keychain reddedildi  -> "Izin ver"
    case invalid             // format bozuk         -> temizle, "Giris yap"
}
```

### 6.6 Erişim prompt'unu azalt

`CodexBar` deseni: Keychain okumasını **30 dakika TTL'li bellek önbelleği**
arkasına al. 60 saniyede bir sorgulama yapan bir menü çubuğu uygulaması, günde
1440 kez Keychain'e gitmemeli.

### 6.7 `organizationID` nereye?

`organizationID` hassas değil, `UserDefaults`'ta durabilir (`TadelUnso` deseni).
`SessionStore.Session` yapısını ikiye böl: anahtar Keychain'e, org id ve
`savedAt` `UserDefaults`'a.

---

## 7. DMG dağıtımı ve notarization

> **Bu bölüm araştırma çıktısında yoktu.** Aşağıdakiler genel macOS dağıtım
> bilgisi. Rakamları ve Apple politikalarını uygulamadan önce güncel Apple
> dokümantasyonundan teyit et.

### 7.1 Minimum gereksinimler

| Gereksinim | Detay | Maliyet |
|---|---|---|
| Apple Developer Program üyeliği | Developer ID sertifikası almanın tek yolu | **99 USD/yıl** |
| Developer ID Application sertifikası | Uygulamayı imzalamak için | Üyelikte dahil |
| Developer ID Installer sertifikası | Yalnızca `.pkg` yaparsan. DMG için gerekmez | Üyelikte dahil |
| Hardened Runtime | Notarization'ın **ön koşulu** | Ücretsiz |
| `notarytool` | Xcode Command Line Tools içinde | Ücretsiz |
| App-specific password veya API key | `notarytool` kimlik doğrulaması | Ücretsiz |

Notarization işleminin kendisi ücretsiz ve sınırsız.

### 7.2 Akış

```bash
# 1. Imzala. Hardened runtime ZORUNLU (--options runtime), yoksa notarization reddeder.
#    --timestamp ZORUNLU: guvenilir zaman damgasi olmadan notarization reddeder.
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Adin Soyadin (TEAMID)" \
  build/ClaudeTakip.app

# 2. DMG uret.
hdiutil create -volname "ClaudeTakip" \
  -srcfolder build/ClaudeTakip.app \
  -ov -format UDZO \
  build/ClaudeTakip.dmg

# 3. DMG'yi de imzala (DMG'nin kendisi de Gatekeeper tarafindan kontrol ediliyor).
codesign --force --sign "Developer ID Application: Adin Soyadin (TEAMID)" \
  build/ClaudeTakip.dmg

# 4. Notarize et ve bekle.
xcrun notarytool submit build/ClaudeTakip.dmg \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

# 5. Bileti DMG'ye zimbala. Bu adim ATLANIRSA cevrimdisi kullanicida
#    Gatekeeper bileti dogrulayamaz ve uygulama acilmaz.
xcrun stapler staple build/ClaudeTakip.dmg

# 6. Dogrula.
xcrun stapler validate build/ClaudeTakip.dmg
spctl --assess --type open --context context:primary-signature -v build/ClaudeTakip.dmg
```

### 7.3 Entitlements

WKWebView ve ağ erişimi için gereken minimum set. App Sandbox **zorunlu değil**
(DMG dağıtımı App Store dışı), ama açarsan Keychain paylaşımı için ek yapılandırma
gerekir.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
```

Sandbox açarsan ayrıca `com.apple.security.app-sandbox` ve Keychain için
`keychain-access-groups` gerekir. **Öneri: ilk sürümde sandbox açma.** Menü
çubuğu uygulaması, DMG dağıtımı, App Store yok. Sandbox sadece Keychain ve
WebView veri deposu konularında ek sürtünme üretir.

### 7.4 Notarize edilmezse kullanıcı deneyimi

Bu bölüm kararı belirleyen kısım.

| Durum | Kullanıcı ne görür |
|---|---|
| **İmzasız + notarize edilmemiş** | "ClaudeTakip is damaged and can't be opened. You should move it to the Trash." Uygulama bozuk değil, Gatekeeper mesajı yanıltıcı. Kullanıcıların çoğu burada vazgeçer |
| **Developer ID imzalı, notarize edilmemiş** | "ClaudeTakip can't be opened because Apple cannot check it for malicious software." |
| **İmzalı + notarize + stapled** | Normal açılır. Tek engel ilk açılışta "downloaded from the Internet" onayı |

**Kritik detay (macOS 15 Sequoia ve sonrası):** eskiden bilinen "sağ tık > Aç"
kaçamağı **kaldırıldı**. Artık kullanıcı şunu yapmak zorunda:

1. Uygulamayı aç, engellensin
2. **Sistem Ayarları > Gizlilik ve Güvenlik**'i aç
3. Aşağı kaydır, "ClaudeTakip engellendi" satırını bul
4. "Yine de Aç"a tıkla
5. Yönetici parolasını gir
6. Uygulamayı **tekrar** aç

Altı adım, biri parola girişi. Bir menü çubuğu kullanım takipçisi için bu kabul
edilemez sürtünme. **Notarize et.** 99 USD/yıl bu adımların tamamını siliyor.

### 7.5 Kısa vadeli alternatif

Henüz Developer hesabı yoksa, ürün doğrulanana kadar:

- **Homebrew Cask** ile dağıt. `brew install --cask` ile kurulanlarda kullanıcı
  zaten terminaldedir, `xattr -dr com.apple.quarantine` talimatı vermek kabul
  edilebilir.
- Veya kaynak dağıt: kullanıcı `swift build` çalıştırsın. Yerel derlemede
  quarantine bayrağı hiç konmaz.

Genel kullanıcıya DMG vereceksen notarization pazarlık konusu değil.

---

## 8. Riskler ve doğrulanmamış noktalar

Bu bölüm doğrulama turunun çıktısını birebir yansıtır.

### 8.1 Çürütülen iddialar (ilk araştırmada yanlıştı)

| # | İddia | Gerçek |
|---|---|---|
| 1 | "Cookie yolu kısa ömürlü, depolardaki `KeychainMigrationService` ve `SessionKeyValidator` bunu kanıtlıyor" | **Kanıt geçersiz.** İlki tek seferlik depolama taşıması (dosya/UserDefaults -> Keychain, `keychainMigrationCompleted_v1` bayrağı), ikincisi format/XSS doğrulayıcısı. İkisi de oturum ömrüyle ilgisiz. Usage4Claude'daki otomatik yenileme **Codex** tarafında, Claude'da değil. **Sonuç yine de doğru**, ama farklı kanıtla: CodexBar issue #1287 |
| 2 | "`javaScriptCanOpenWindowsAutomatically = true` Google popup'ı için gerekli olabilir" | **macOS'ta varsayılan zaten `true`**, Apple dokümantasyonu ile ve ölçümle teyit edildi. Bayrak `false` iken bile jest olmayan `window.open` `createWebViewWith`'i tetikledi. Satır no-op |
| 3 | "UA spoofing kanıtları eski ve masaüstü/Electron kaynaklı, `flutter_inappwebview#1112` bunu gösteriyor" | **Kaynak ters okunmuş.** O thread'de birden çok kullanıcı `userAgent: 'random'` ile sorunun **çözüldüğünü** bildiriyor ve depo sahibi bunu "the right solution" diye onaylıyor. Ayrıca thread tamamen **Android**, iOS değil |
| 4 | "Apple ile giriş tam sayfa redirect, bu yüzden WKWebView'de çalışması beklenir" | **Çıkarım geçersiz.** Apple forum thread/740376 birebir "iOS 17.1 breaks Sign-In with Apple (JavaScript) within WKWebView". Ayrıca bundle gözlemleri tek seferlik ve tekrarlanamaz (claude.ai curl'e 403 Turnstile veriyor) |
| 5 | "`UIApplication.open` yerine `ASWebAuthenticationSession` kullanın, yoksa App Store reddi" | **Kaynak kendisiyle çelişiyor.** thread/750400'de reddedilen uygulamalar **zaten** `ASWebAuthenticationSession` kullanıyordu ve tam da bu yüzden reddedildiler. macOS'a özgü, ve biz DMG ile dağıtıyoruz |
| 6 | "`/v1/messages` başlıkları, sessionKey'e dokunmadan kota okumanın **resmî API tabanlı** yolu" | **En ciddi hata.** O kod yolu abonelik OAuth token'ı kullanıyor (`Bearer` + `User-Agent: claude-code/2.1.5`) ve salt okuma değil: gerçek bir **POST inference** çağrısı yapıyor (`claude-haiku-4-5`, `max_tokens: 1`, "hi"). Bu tam olarak Anthropic'in Şubat 2026'da yasakladığı desen. `sessionKey` yolundan **daha riskli** |
| 7 | "`applicationNameForUserAgent` işe yaramaz, `customUserAgent` gerekir" | **Ölçümle çürütüldü.** Webview'dan önce config'e set edilirse UA gerçek Safari ile bayt bayt aynı oluyor |

### 8.2 Çözülmemiş çelişkiler

| Konu | Taraf A | Taraf B | Durum |
|---|---|---|---|
| `createWebViewWith`'te hangi configuration | dowoonlee + hamed-elfayome: "WebKit'in verdiğini kullan, yoksa `window.opener` kopar" | vibe-bar: kendi configuration'ını üretiyor. Usage4Claude + TheMarco: popup'ı hiç açmıyor | **Karşılaştırmalı test yok.** Muhtemelen claude.ai'nin Google akışı zamanla değişti ve depolar farklı dönemleri yansıtıyor. A'da iki bağımsız gerekçe var, B ve C'de sıfır |
| URLSession'da tam cookie header | Usage4Claude: `cf_clearance` dahil hepsini gönder | AIQuotaBar: CF çerezlerini strip et, yoksa 403 | **Çözülmedi.** Muhtemel açıklama: Usage4Claude çerezleri taze alıyor, AIQuotaBar eskimiş çerezlerle uğraşıyor |
| `api.anthropic.com/api/oauth/usage` durumu | Usage4Claude hâlâ kullanıyor (`ClaudeOAuthConfig.swift:31`) | hamed-elfayome kod yorumu birebir: "The dedicated OAuth usage endpoint (api.anthropic.com/api/oauth/usage) is disabled." | **Çözülmedi.** Bizi doğrudan etkilemiyor (cookie yolundayız) ama OAuth'a geçmeyi düşünürsen önce bunu netleştir |
| `/api/oauth/usage` rate limit | TadelUnso: "ayrı ve yapışkan bir Cloudflare rate limit'i var" | ccseva ve OpenUsage sorunsuz kullanıyor | **Tek kaynaklı iddia, doğrulanmadı** |

### 8.3 Hiç test edilmemiş noktalar

1. **Kişisel Gmail hesabıyla gömülü WKWebView'da uçtan uca giriş.** Hiçbir depoda
   açık test kaydı yok. **Kalan tek belirleyici bilinmeyen. Önce bunu ölç.**
2. **`window.opener` null regresyonu macOS'ta var mı?** iOS 17.5+ için DOĞRULANDI
   ve Apple çözemedi. macOS testi yok. Varsa GIS popup akışı UA ne olursa olsun
   tamamlanamaz.
3. **`sessionKey`'in gerçek sunucu tarafı ömrü.** "1 ay" bir `max-age` beyanı,
   tek blog kaynağı. Gerçek kadans CodexBar issue #1287'ye göre çok daha kısa
   olabilir.
4. **Passkey/WebAuthn gömülü WKWebView'da.** Kesin çalışmıyor gibi görünüyor
   (Usage4Claude kod yorumu, vibe-bar'ın ayrı "tarayıcıda aç" düğmesi) ama
   doğrudan test kaydı yok. Kullanıcı tabanın passkey kullanıyorsa gömülü yol
   baştan elenir.
5. **claude.ai bugün hâlâ GIS popup mu kullanıyor?** Bundle analizi 2026-08-23
   itibarıyla evet diyor (`popup_closed` kanıtı). Tam sayfa redirect'e geçerse
   `createWebViewWith` hiç tetiklenmez ve tüm popup mimarisi gereksizleşir.
   Anthropic bunu bildirmez, kırılınca öğrenirsin.
6. **Kurumsal Google hesapları çalışmıyor (bu DOĞRULANDI).** Kullanıcın Workspace
   hesabı kullanıyorsa Google yolunu hiç önerme, doğrudan magic link'e yönlendir.

### 8.4 ToS riski (dürüst değerlendirme)

**DOĞRULANDI, Anthropic Consumer Terms Bölüm 3, birebir:**

> "Except when you are accessing our Services via an Anthropic API Key or where we
> otherwise explicitly permit it, to access the Services through automated or
> non-human means, whether through a bot, script, or otherwise."

Aynı bölümde crawl/scrape yasağı, Bölüm 2'de kimlik bilgisi paylaşımı yasağı var.
`sessionKey` ile bu uçları çağırmak **lafzen bu maddelere giriyor**.

**OAuth yolu daha güvenli değil.** Anthropic'in kendi yardım merkezi
(`support.claude.com/en/articles/15036540`) OAuth kimlik doğrulamasının yalnızca
Claude Code ve diğer yerel Anthropic uygulamaları için olduğunu, ürün geliştirenlerin
Console API anahtarı kullanması gerektiğini söylüyor. 9 Ocak 2026'da sunucu tarafı
blok geldi, ToS metni Şubat 2026'da yayımlandı.

**Gözlemlenen yaptırım profili farklı bir davranışı hedefliyor.** Bilinen tüm
vakalar (OpenClaw ve benzeri harness'ler) abonelik kimlik bilgisiyle **model
çağırma** üzerine. Salt-okunur kota sorgulaması için belgelenmiş tek bir ban
örneği bulunamadı. Ve `CodexBar` (20.5k yıldız) ile `Claude-Usage-Tracker`
(3.3k yıldız) bu uçları aylardır aktif kullanıyor.

**Ama:** MindStudio analizinin saydığı üç tespit mekanizmasından ikisi (cookie
reuse, iç web API'yi doğrudan çağırma) tam olarak bizim yaptığımız şey. Inference
yapmasak bile. Kanıt yokluğu, yokluk kanıtı değil.

**Karar:** kişisel kullanım için makul risk. Ama:

- Uygulamayı **halka açık dağıtırken** bu riski README'de açıkça yaz
- Sorgulama sıklığını 60 saniyenin altına indirme
- Hiçbir koşulda inference çağrısı ekleme (8.1 #6'daki tuzak)
- Kullanıcının çerezini hiçbir yere gönderme, her şey yerelde kalsın

---

## 9. Uygulama sırası

Bağımlılığa göre sıralandı. Her adımın sonunda çalışan bir şey var.

### Faz 0: Belirleyici bilinmeyeni kapat (yarım gün)

**Bu her şeyden önce gelir.** Google akışı çalışmıyorsa 1. ve 2. fazın mimarisi
değişir.

1. `LoginWindowController`'daki `createWebViewWith`'i B stratejisinden A'ya çevir
   (gerçek popup + verilen configuration). Bölüm 2.3'teki kod.
2. `applicationNameForUserAgent`'ı config'e ekle (webview'dan **önce**).
3. **Kendi kişisel Gmail hesabınla uçtan uca test et.**
4. Sonuç:
   - Çalışıyorsa: devam et.
   - Çalışmıyorsa: `window.opener`'ı `evaluateJavaScript("typeof window.opener")`
     ile popup'ta ölç. Null ise macOS'ta da regresyon var demektir, Google'ı
     kapat ve e-posta magic link'i birincil yol yap (2.7).

### Faz 1: Girişi sağlamlaştır (1 gün)

5. `LoginNavigationPolicy`'yi ekle, frame ayrımıyla (2.2). Birim testini yaz:
   `decide(for: hcaptchaURL, isMainFrame: false) == .allow`.
6. Dört tetikleyiciyi de bağla: `didFinish`, `didReceiveServerRedirect`,
   `webViewDidClose`, 1 sn timer (2.5).
7. `captured` bayrağı ile çift tetikleme savunması (2.4).
8. `windowWillClose`'da popup temizliği (kullanıcı OAuth'u iptal ederse).
9. Çerezi kaydetmeden önce `/api/organizations` ile doğrula (5.4).

### Faz 2: API katmanını düzelt (1 gün)

10. **403'ü 401'den ayır.** `classifyForbidden` ekle, `cloudflareChallenge`
    hata tipini tanıt (4.5). Bu, kullanıcıyı sonsuz giriş döngüsünden kurtaran
    tek değişiklik.
11. **Org seçimini düzelt.** `list.first` yerine `capabilities` filtreli seçim
    (3.2).
12. **`seven_day_omelette`'i kaldır.** Ana `seven_day` ile aynı havuz, iki kez
    gösteriyoruz (3.3).
13. **`extra_usage` birimini düzelt.** Sent cinsinden, 100'e böl. `resets_at`
    yok, ayın 1'ini (UTC) kendin hesapla (3.4).
14. `SessionKeyRenewalTracker` ekle, 200 yanıtlarındaki `Set-Cookie`'yi izle ve
    yeni anahtarı depoya yaz (5.3).
15. Başlıkları sadeleştir: `Cookie` + `Accept` yeterli. CF çerezlerini gönderme
    (4.1, 4.2).
16. Sorgulama aralığını 60 saniyeye sabitle, 429'da `Retry-After`'a uy (4.7).

### Faz 3: Saklamayı taşı (yarım gün)

17. `KeychainSessionStore`'u yaz (6.4).
18. `CredentialState` durum makinesini ekle: `available/notFound/permissionRequired/invalid`
    (6.5).
19. Mevcut dosya deposundan tek seferlik geçiş yaz (dosya varsa oku, Keychain'e
    yaz, dosyayı sil).
20. 30 dakika TTL'li bellek önbelleği ekle (6.6).
21. `organizationID`'yi `UserDefaults`'a ayır (6.7).

**Not:** bu fazı Faz 5'ten (imzalama) **önce** yaparsan geliştirme sırasında
Keychain prompt'u yiyeceksin. İki seçenek: ya Faz 5'ten sonraya al, ya da
geliştirme derlemesi için dosya yoluna düşen bir `#if DEBUG` dalı bırak.
İkincisi daha iyi, Usage4Claude da öyle yapıyor.

### Faz 4: UX (1 gün)

22. Dört durum için popover görünümlerini ayır (5.5).
23. `sessionExpired`'da pencereyi **otomatik açma**, düğme göster.
24. `cloudflareChallenge` için ayrı mesaj: "VPN kullanıyorsan kapat."
25. Son bilinen değeri zaman damgasıyla sakla ve soluk göster.
26. `checkExistingCookie` deseni: girişliyse pencereyi hiç gösterme.

### Faz 5: Dağıtım (1 gün + notarization bekleme)

27. Apple Developer Program üyeliğini al (99 USD/yıl).
28. Developer ID Application sertifikasını indir.
29. Hardened Runtime + `--timestamp` ile imzala.
30. DMG üret, DMG'yi de imzala.
31. `notarytool submit --wait`, sonra `stapler staple`.
32. `stapler validate` ve `spctl --assess` ile doğrula.
33. **Temiz bir Mac'te test et** (veya `xattr -w com.apple.quarantine` ile
    quarantine bayrağını elle koy). Kendi geliştirme makinende Gatekeeper
    davranışı farklıdır.

### Yapma listesi

| Yapma | Neden |
|---|---|
| `javaScriptCanOpenWindowsAutomatically` yazma | macOS'ta zaten `true`, no-op (8.1 #2) |
| `/v1/messages` ile kota okuma | POST inference çağrısı, ToS açısından en riskli desen (8.1 #6) |
| UA'ya `Claude/x.y.z` ekleyip `window.claudeAppBindings` tanımlama | claude.ai'nin platform tespiti bununla `desktop` yoluna geçiyor, ama bu Anthropic'in resmî istemcisini taklit etmek. Ayrı ve ciddi bir risk |
| `dowoonlee` veya `vibe-bar` kodunu kopyalama | Biri lisanssız (tüm haklar saklı), diğeri AGPL-3.0 (viral). Fikir al, kod alma. Kod için `matjam/headroom` (MIT) |
| Cloudflare 403'ünde "yeniden giriş yap" gösterme | Sonsuz döngü. Kullanıcı girer, yine 403 alır (4.5) |
| 30 saniyenin altında sorgulama | Kazanç yok, rate limit riski var (4.7) |
| Notarization'ı atlama | macOS 15'te kullanıcı 6 adım + parola girmek zorunda (7.4) |
