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
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        context.coordinator.mainWebView = webView
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

        // MARK: - WKUIDelegate — Google OAuth popup

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Create a real child WKWebView so Claude's JS sees a successful popup
            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.customUserAgent = webView.customUserAgent
            popup.autoresizingMask = [.width, .height]

            // Replace the main WebView's content with the popup
            // (swap views so popup renders in the same window)
            if let superview = webView.superview {
                webView.removeFromSuperview()
                superview.addSubview(popup)
            }

            popupWebView = popup
            return popup
        }

        // Handle popup close — restore main WebView
        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popupWebView, let main = mainWebView else { return }
            if let superview = webView.superview {
                webView.removeFromSuperview()
                superview.addSubview(main)
                main.frame = superview.bounds
                main.autoresizingMask = [.width, .height]
            }
            popupWebView = nil
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isExtracted else { return }
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
            guard !isExtracted else { return }
            checkForSessionCookie(webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
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
            // Reload main to pick up the new session
            main.load(URLRequest(url: URL(string: "https://claude.ai")!))
            popupWebView = nil
        }

        private func startPeriodicCheck(webView: WKWebView) {
            guard cookieCheckTimer == nil else { return }
            cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isExtracted else {
                        self?.stopTimer()
                        return
                    }
                    // Check cookies from both main and popup WebViews
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
