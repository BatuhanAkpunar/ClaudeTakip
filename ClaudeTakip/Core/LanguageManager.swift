import Foundation

enum LanguageManager {
    nonisolated(unsafe) private(set) static var bundle: Bundle = .main

    static func apply(_ code: String?) {
        if let code,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
    }
}

extension Bundle {
    /// Shorthand for LanguageManager.bundle — use as `bundle: .app`
    static var app: Bundle { LanguageManager.bundle }
}
