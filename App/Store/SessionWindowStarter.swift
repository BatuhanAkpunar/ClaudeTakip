import Foundation
import LimitCore

/// Pencere kapandığında kendiliğinden yeni pencere açma. Varsayılan KAPALI (açık onay).
///
/// Bu, uygulamanın kullanıcı hesabından içerik ürettiği tek özellik.
/// Kontrol TEK yerde (`startIfNeeded`), böylece "kapattım ama yine de
/// gönderiyor" durumu oluşamıyor: kapalıyken hiçbir yoldan istek çıkmıyor.
@MainActor
final class SessionWindowStarter {
    enum State: Equatable {
        case idle
        case running
        case done(Date)
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { onChange(state) }
    }

    /// Her durum değişiminde çağrılır; store gözlenen kopyasını buradan günceller.
    var onChange: @MainActor (State) -> Void = { _ in }

    /// Son başlatma denemesi. Tekrar tekrar göndermeyi engelliyor.
    private var lastStart: Date?
    /// İki deneme arasındaki en kısa süre. Sunucunun yeni pencereyi
    /// raporlaması birkaç tur sürebiliyor; bu aralık olmadan pencere açıkken
    /// bile üst üste istek gider.
    private static let cooldown: TimeInterval = 10 * 60
    /// Uçuştaki başlatma. Çıkışta iptal edilir: aksi halde oluşturma,
    /// completion ve silme istekleri çıkılmış oturumun anahtarıyla sürer.
    private var task: Task<Void, Never>?

    /// Uçuştaki başlatmayı iptal eder (çıkış).
    func cancel() {
        task?.cancel()
        task = nil
        if state == .running { state = .idle }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.autoSessionEnabled) as? Bool
            ?? SettingsKey.autoSessionDefault
    }

    /// Otomatik yol: yalnızca ayar AÇIKSA ve pencere gerçekten KAPALIYSA.
    /// Sabit aralıklı koşulsuz ping YOK; tetikleyici pencerenin kapalı olması.
    ///
    /// `credentials` yalnızca girişliyken ve kuruluş kimliği biliniyorken dolu.
    /// `isCurrent`, yanıt döndüğünde oturumun hâlâ aynı olup olmadığını söyler.
    func startIfNeeded(
        windowClosed: Bool,
        credentials: (sessionKey: String, organizationID: String)?,
        isCurrent: @escaping @MainActor () -> Bool,
        onStarted: @escaping @MainActor () -> Void
    ) {
        guard isEnabled, windowClosed else { return }
        if let last = lastStart,
           Date().timeIntervalSince(last) < Self.cooldown { return }
        guard let credentials else {
            state = .failed(L.t("Giriş gerekiyor.", "Sign in required."))
            return
        }
        guard state != .running else { return }

        lastStart = Date()
        state = .running

        task = Task { [weak self] in
            let client = ClaudeWebClient(sessionKey: credentials.sessionKey)
            do {
                try await client.startSessionWindow(organizationID: credentials.organizationID)
                guard let self, isCurrent() else { return }
                self.state = .done(Date())
                // Yeni pencereyi hemen doğrula.
                onStarted()
            } catch {
                guard let self, isCurrent() else { return }
                self.state = .failed(
                    L.t("Pencere başlatılamadı.", "Could not start the window.")
                )
            }
        }
    }
}
