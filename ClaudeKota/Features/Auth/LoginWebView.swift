import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let onCookieExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Default data store — OAuth redirect'leri icin gerekli
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Google OAuth, embedded browser'lari user-agent'tan tespit edip engelliyor.
        // Safari user-agent kullanarak bunu atlat.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieExtracted: onCookieExtracted)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookieExtracted: (String) -> Void
        private var isExtracted = false
        private var cookieCheckTimer: Timer?

        init(onCookieExtracted: @escaping (String) -> Void) {
            self.onCookieExtracted = onCookieExtracted
        }

        func stopTimer() {
            cookieCheckTimer?.invalidate()
            cookieCheckTimer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isExtracted else { return }
            checkForSessionCookie(webView: webView)
            startPeriodicCheck(webView: webView)
        }

        // Redirect sirasinda da cookie kontrol et
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            guard !isExtracted else { return }
            checkForSessionCookie(webView: webView)
        }

        private func startPeriodicCheck(webView: WKWebView) {
            guard cookieCheckTimer == nil else { return }
            cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isExtracted else {
                        self?.stopTimer()
                        return
                    }
                    self.checkForSessionCookie(webView: webView)
                }
            }
        }

        private func checkForSessionCookie(webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor [weak self] in
                    guard let self, !self.isExtracted else { return }
                    if let sessionCookie = cookies.first(where: {
                        $0.name == "sessionKey" && $0.domain.contains("claude.ai")
                    }) {
                        self.isExtracted = true
                        self.stopTimer()
                        self.onCookieExtracted(sessionCookie.value)
                    }
                }
            }
        }
    }
}
