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

        // Google, GitHub gibi OAuth provider'lari WKWebView'u engelliyor — browser'a yonlendir
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .allow
            }

            let host = url.host ?? ""

            if host.contains("accounts.google.com") ||
               host.contains("github.com/login") ||
               host.contains("appleid.apple.com") {
                NSWorkspace.shared.open(url)
                return .cancel
            }

            return .allow
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
