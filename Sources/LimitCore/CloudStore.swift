import Foundation

/// Bulut senkron kimliği.
///
/// Hesap değil, cihaz kimliği: kullanıcıdan e-posta veya parola istenmiyor.
/// Gizli anahtar yalnızca bu cihazın kendi verisine yazma yetkisi veriyor,
/// Claude hesabıyla hiçbir ilgisi yok.
public struct CloudIdentity: Codable, Sendable, Equatable {
    public let deviceID: String
    public let secret: String

    var bearer: String { "\(deviceID).\(secret)" }
}

/// Cihaz kimliğini ve yükleme işaretini diskte tutar.
public struct CloudStore: Sendable {
    public static var defaultURL: URL {
        StoragePaths.appSupport.appendingPathComponent("cloud.json")
    }

    private struct State: Codable {
        var identity: CloudIdentity?
        /// En son buluta yazılan örneğin zamanı. Her seferinde baştan
        /// göndermemek için.
        var uploadedThrough: Date?
        /// Verinin bağlı olduğu hesap anahtarı. nil ise veri anonim, yalnızca
        /// bu cihaza ait. Giriş yapıldığında doluyor ve o andan sonra kanonik
        /// sahip hesap oluyor.
        var accountKey: String?
    }

    public let url: URL

    public init(url: URL = CloudStore.defaultURL) {
        self.url = url
    }

    private func load() -> State {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    private func write(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        // Adımlar bağımsız: dizin adımı başarısız olsa da yazım denenir.
        try? PrivateFile.ensureDirectory(for: url)
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public var identity: CloudIdentity? { load().identity }
    public var uploadedThrough: Date? { load().uploadedThrough }
    public var accountKey: String? { load().accountKey }

    public func save(identity: CloudIdentity) {
        var state = load()
        state.identity = identity
        write(state)
    }

    public func save(uploadedThrough: Date) {
        var state = load()
        state.uploadedThrough = uploadedThrough
        write(state)
    }

    /// Hesap anahtarını yazar. nil vermek hesabı bırakır (çıkış).
    public func save(accountKey: String?) {
        var state = load()
        state.accountKey = accountKey
        write(state)
    }

    /// Yükleme işaretini sıfırlar.
    ///
    /// Hesap benimsendiğinde bir kez çağrılıyor: daha önce hiç yüklenmemiş
    /// yerel satırlar (senkron kapalıyken birikenler, başarısız yüklemeler)
    /// da hesabın altına gitsin. Yükleme idempotent olduğu için tekrar
    /// göndermek güvenli.
    public func resetWatermark() {
        var state = load()
        state.uploadedThrough = nil
        write(state)
    }

    /// Cihaz kimliğini ve yükleme işaretini atar, hesap anahtarını KORUR.
    ///
    /// Sunucu cihazı tanımadığında (`notRegistered`) çağrılıyor: bir sonraki
    /// turda yeniden kaydolunur ve veri hâlâ girişli hesabın altına gider.
    /// `clear()` hesap anahtarını da düşürüyordu; bir sonraki sunucu okumasına
    /// kadar yüklemeler anonim kalıyordu.
    public func clearIdentity() {
        var state = load()
        state.identity = nil
        state.uploadedThrough = nil
        write(state)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
