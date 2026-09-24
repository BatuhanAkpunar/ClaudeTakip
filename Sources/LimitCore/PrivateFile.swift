import Foundation

/// Yalnızca kullanıcının okuyabildiği dosya yazımı: dizin 0700, dosya 0600.
enum PrivateFile {
    static func ensureDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func write(_ data: Data, to url: URL) throws {
        try ensureDirectory(for: url)
        // `.completeFileProtection` KULLANILMIYOR: iOS'a ait bir dosya
        // koruma sınıfı ve macOS'ta yazmayı "Operation not permitted" ile
        // tamamen engelliyor; oturum anahtarı hiç kaydedilemez. Koruma
        // POSIX 0600 ile sağlanıyor.
        try data.write(to: url, options: [.atomic])
        // Atomik yazım dosyayı yeniden yarattığı için izinler sonradan konuyor.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
