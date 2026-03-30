import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let onCookieExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieExtracted: onCookieExtracted)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookieExtracted: (String) -> Void
        private var isExtracted = false

        init(onCookieExtracted: @escaping (String) -> Void) {
            self.onCookieExtracted = onCookieExtracted
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isExtracted else { return }
            checkForSessionCookie(webView: webView)
        }

        private func checkForSessionCookie(webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.isExtracted else { return }
                if let sessionCookie = cookies.first(where: {
                    $0.name == "sessionKey" && $0.domain.contains("claude.ai")
                }) {
                    self.isExtracted = true
                    Task { @MainActor in
                        self.onCookieExtracted(sessionCookie.value)
                    }
                }
            }
        }
    }
}
