import AppKit
import WebKit
import LimitCore

/// claude.ai giriş penceresi.
///
/// Giriş popover'ın içinde değil ayrı bir pencerede yapılıyor. Popover
/// `.transient`, yani dışına tıklandığında kapanıyor ve 360 pt genişliğinde:
/// bir giriş formu için ikisi de uygun değil. Ayrı pencere sayesinde popover
/// akış boyunca hiç yeniden boyutlanmıyor.
///
/// Akış MIT lisanslı `theDanButuc/Claude-Usage-Monitor` projesindeki desenle
/// aynı: WKWebView'de oturum açılıyor, `sessionKey` çerezi yakalanınca pencere
/// kapanıyor ve sonrasında tüm istekler düz `URLSession` ile gidiyor.
@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var popupWindow: NSWindow?
    private var popupWebView: WKWebView?
    private var pollTimer: Timer?
    /// Yakalanan anahtar ve çerezin son kullanma tarihi (varsa).
    private let onSuccess: (String, Date?) -> Void
    /// Pencere kapandığında (başarıyla ya da iptalle) haber verir. Sahibin
    /// referansı bırakabilmesi için gerekli.
    private let onDismiss: () -> Void

    init(onSuccess: @escaping (String, Date?) -> Void, onDismiss: @escaping () -> Void = {}) {
        self.onSuccess = onSuccess
        self.onDismiss = onDismiss
        super.init()
    }

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let configuration = WKWebViewConfiguration()
        // Boş depo: hiçbir sağlayıcıda önceden oturum olmasın, yoksa Google
        // sessizce eski hesaba giriş yapıp kullanıcıya seçim sunmuyor.
        // Çerezi zaten kendimiz saklıyoruz, bu deponun kalıcı olmasına gerek yok.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: configuration)
        // Google gömülü webview tespit ederse OAuth'u 403 ile reddediyor.
        webView.customUserAgent = ClaudeWebClient.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        // Popup delegesi olmadan Google girişi sessizce hiçbir şey yapmıyor.
        webView.uiDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        self.webView = webView

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L.t("Claude'a Giriş", "Sign in to Claude")
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Giriş sonrası yönlendirmeler birden çok adımda olabiliyor ve çerez
        // navigasyon bittiği anda hazır olmayabiliyor; yoklama bunu kaçırmıyor.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForSession() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkForSession() {
        // Popup açıksa çerez oraya yazılıyor olabilir; ikisi de aynı veri
        // deposunu paylaştığı için hangisi elde varsa ondan sorulabilir.
        guard let webView = popupWebView ?? webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            guard let cookie = cookies.first(where: {
                // `contains` yerine sonek eşleşmesi: "claude.ai.kotu-site.com"
                // gibi bir alan adı `contains` denetimini geçiyordu.
                $0.name == "sessionKey" && Self.isClaudeDomain($0.domain)
            }) else { return }
            // Çıkış yapıldığında çerez boş bir değerle yeniden yazılabiliyor;
            // gerçek anahtar her zaman `sk-ant-` ile başlıyor.
            guard cookie.value.count > 20, cookie.value.hasPrefix("sk-ant-") else { return }
            Task { @MainActor in self.finish(with: cookie.value, expiresAt: cookie.expiresDate) }
        }
    }

    /// Çerez gerçekten claude.ai'ye mi ait.
    ///
    /// Çerez alan adları başında noktayla gelebiliyor (".claude.ai"), bu yüzden
    /// hem tam eşleşme hem de nokta önekli sonek kabul ediliyor.
    static func isClaudeDomain(_ domain: String) -> Bool {
        let host = ClaudeWebClient.host
        return domain == host || domain == "." + host || domain.hasSuffix("." + host)
    }

    private func finish(with sessionKey: String, expiresAt: Date?) {
        guard pollTimer != nil else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        // Son kullanma tarihi eskiden atılıyordu; oysa "oturum N gün sonra
        // dolacak" uyarısının tek kaynağı bu.
        onSuccess(sessionKey, expiresAt)
        close()
    }

    func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        closePopup()
        onDismiss()
    }

    func windowWillClose(_ notification: Notification) {
        // Kullanıcı yetkilendirmeyi iptal edip popup'ı elle kapatırsa
        // `webViewDidClose` tetiklenmiyor, emniyet ağı burada.
        if (notification.object as? NSWindow) === popupWindow {
            popupWindow = nil
            popupWebView = nil
            return
        }
        closePopup()
        pollTimer?.invalidate()
        pollTimer = nil
        window = nil
        webView = nil
        onDismiss()
    }
}

extension LoginWindowController: WKNavigationDelegate {
    /// Sayfa hiç açılamadığında kullanıcı boş beyaz bir pencereye bakıyordu ve
    /// ne olduğunu anlamıyordu: ağ yoksa, DNS düşmüşse ya da claude.ai
    /// erişilemiyorsa hiçbir geri bildirim yoktu.
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailure(error)
    }

    private func showLoadFailure(_ error: Error) {
        // İptal edilen yüklemeler gerçek hata değil: yönlendirme zincirinde
        // normal olarak oluşuyor ve uyarı göstermek kullanıcıyı yanıltır.
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        guard let window, window.isVisible else { return }

        let alert = NSAlert()
        alert.messageText = L.t("Giriş sayfası açılamadı", "Could not open the sign-in page")
        alert.informativeText = L.t(
            "İnternet bağlantını kontrol edip yeniden dene.\n\n\(error.localizedDescription)",
            "Check your internet connection and try again.\n\n\(error.localizedDescription)"
        )
        alert.addButton(withTitle: L.t("Yeniden dene", "Retry"))
        alert.addButton(withTitle: L.t("Kapat", "Close"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.webView?.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
            } else {
                window.close()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    /// Yönlendirmeler sırasında da çereze bakılıyor: giriş bittiğinde sayfa
    /// yüklenmesi tamamlanmadan önce çerez yazılmış olabiliyor.
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        checkForSession()
    }
}

extension LoginWindowController: WKUIDelegate {
    /// `window.open()` ile açılmak istenen pencereleri karşılar.
    ///
    /// claude.ai'nin "Continue with Google" düğmesi Google Identity Services
    /// SDK'sı ve `ux_mode` verilmediği için accounts.google.com'u POPUP olarak
    /// açıyor. Bu delege yoksa `window.open()` sessizce iptal ediliyor: ne
    /// pencere ne hata çıkıyor, düğme ölü görünüyor.
    ///
    /// GELEN `configuration` AYNEN KULLANILMALI, yenisi üretilmemeli. WebKit
    /// açan sayfa ile aynı veri deposunu ve process pool'unu bu nesne üzerinden
    /// devrediyor. Yeni configuration üretilirse iki şey birden bozuluyor:
    /// popup ayrı bir çerez deposuna yazar ve bizim yoklamamız giriş çerezini
    /// hiç göremez; ayrıca `window.opener` kopar ve Google'ın sonucu açan
    /// sayfaya `postMessage` ile döndürmesi tamamlanmaz.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Çift tık savunması: açık popup varsa yenisini yaratma.
        if let existing = popupWebView {
            popupWindow?.makeKeyAndOrderFront(nil)
            return existing
        }

        let popup = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 640),
            configuration: configuration
        )
        // Popup içinde ikinci bir window.open olabilir, delegeler taşınıyor.
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.customUserAgent = webView.customUserAgent

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

        // İsteği WebKit döndürülen görünüme kendisi yüklüyor; burada load()
        // çağırmak çift yükleme yapar.
        return popup
    }

    /// Popup `window.close()` çağırdığında, yani yetkilendirme bittiğinde gelir.
    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        closePopup()
        // Popup kapanırken çerez zaten depoya yazılmış oluyor, bir saniyelik
        // yoklamayı beklemeden hemen bakılıyor.
        checkForSession()
    }

    private func closePopup() {
        popupWindow?.delegate = nil
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }
}
