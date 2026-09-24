import Foundation

/// Diskteki yerleşim tek yerde.
enum StoragePaths {
    static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    /// Uygulamanın kendi verisi. "Claude Limit" eski ürün adı; değiştirmek
    /// mevcut kullanıcı verisini yetim bırakır.
    static var appSupport: URL { home.appendingPathComponent("Library/Application Support/Claude Limit") }

    /// Claude Desktop'ın verisi (salt okunur).
    static var claudeDesktopSupport: URL { home.appendingPathComponent("Library/Application Support/Claude") }

    /// Claude Code'un oturum kayıtları (salt okunur).
    static var claudeCodeProjects: URL { home.appendingPathComponent(".claude/projects") }

    /// Claude Code'un hesap yapılandırması (salt okunur).
    static var claudeConfig: URL { home.appendingPathComponent(".claude.json") }
}
