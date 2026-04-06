import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let onCookieExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Hide WKWebView fingerprints before page loads
        let antiDetectScript = WKUserScript(
            source: """
            Object.defineProperty(navigator, 'webdriver', { get: function() { return false; } });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(antiDetectScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        context.coordinator.mainWebView = webView

        // Clear stale claude.ai cookies, then load login page
        context.coordinator.clearCookiesAndLoad(
            webView: webView,
            store: config.websiteDataStore.httpCookieStore
        )

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieExtracted: onCookieExtracted)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onCookieExtracted: (String) -> Void
        private var isExtracted = false
        private var cookiesCleared = false
        private var cookieCheckTimer: Timer?
        weak var mainWebView: WKWebView?
        private var popupWebView: WKWebView?

        init(onCookieExtracted: @escaping (String) -> Void) {
            self.onCookieExtracted = onCookieExtracted
        }

        func stopTimer() {
            cookieCheckTimer?.invalidate()
            cookieCheckTimer = nil
        }

        /// Deletes all claude.ai cookies, then loads the login page.
        func clearCookiesAndLoad(webView: WKWebView, store: WKHTTPCookieStore) {
            store.getAllCookies { [weak self] cookies in
                Task { @MainActor [weak self] in
                    for cookie in cookies where cookie.domain.contains("claude.ai") {
                        await store.delete(cookie)
                    }
                    self?.cookiesCleared = true
                    if let url = URL(string: "https://claude.ai/login") {
                        webView.load(URLRequest(url: url))
                    }
                }
            }
        }

        // MARK: - WKUIDelegate — Google OAuth popup

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.customUserAgent = webView.customUserAgent
            popup.autoresizingMask = [.width, .height]

            if let superview = webView.superview {
                webView.removeFromSuperview()
                superview.addSubview(popup)
            }

            popupWebView = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popupWebView, let main = mainWebView else { return }
            if let superview = webView.superview {
                webView.removeFromSuperview()
                superview.addSubview(main)
                main.frame = superview.bounds
                main.autoresizingMask = [.width, .height]
            }
            popupWebView = nil

            // After OAuth popup closes, check for cookie immediately
            checkForSessionCookie(webView: main)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isExtracted, cookiesCleared else { return }
            checkForSessionCookie(webView: webView)
            startPeriodicCheck(webView: webView)

            // If popup finished on claude.ai, OAuth is done — restore main view
            if webView === popupWebView,
               let url = webView.url,
               url.host?.contains("claude.ai") == true,
               url.path != "/login" {
                restoreMainWebView()
            }
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            guard !isExtracted, cookiesCleared else { return }
            checkForSessionCookie(webView: webView)
        }

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            Task { @MainActor in
                decisionHandler(.allow)
            }
        }

        // MARK: - Private

        private func restoreMainWebView() {
            guard let popup = popupWebView, let main = mainWebView else { return }
            if let superview = popup.superview {
                popup.removeFromSuperview()
                superview.addSubview(main)
                main.frame = superview.bounds
                main.autoresizingMask = [.width, .height]
            }
            if let url = URL(string: "https://claude.ai") {
                main.load(URLRequest(url: url))
            }
            popupWebView = nil
        }

        private func startPeriodicCheck(webView: WKWebView) {
            guard cookieCheckTimer == nil else { return }
            cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isExtracted, self.cookiesCleared else {
                        self?.stopTimer()
                        return
                    }
                    let target = self.popupWebView ?? self.mainWebView
                    if let target { self.checkForSessionCookie(webView: target) }
                }
            }
        }

        private func checkForSessionCookie(webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor [weak self] in
                    guard let self, !self.isExtracted else { return }
                    if let sessionCookie = cookies.first(where: {
                        $0.name == "sessionKey"
                            && ($0.domain == "claude.ai" || $0.domain == ".claude.ai")
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
