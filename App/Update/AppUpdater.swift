import AppKit
import Sparkle

/// Otomatik güncelleme: GitHub'a yeni bir sürüm çıkınca uygulama onu kendisi
/// bulur, indirir, kurar ve yeniden başlar.
///
/// Sparkle kullanılıyor. Güvenlik tek bir şeye dayanıyor: her güncelleme
/// arşivi EdDSA ile imzalı ve imzanın açık anahtarı uygulamanın içinde
/// (`SUPublicEDKey`). İmzası tutmayan arşiv kurulmuyor; yani GitHub hesabı ele
/// geçirilse bile özel anahtar olmadan kimse kullanıcılara kod gönderemez.
/// Özel anahtar yalnızca geliştiricinin makinesinde, repo dışında duruyor
/// (bkz. `tools/release.sh`).
///
/// Denetim sıklığı, besleme adresi ve "sessizce kur" ayarları Info.plist'te
/// (`project.yml`).
@MainActor
final class AppUpdater: NSObject {
    private var controller: SPUStandardUpdaterController?
    private let isPopoverShown: () -> Bool
    /// Popover açıkken gelen kurulum, popover kapanınca yapılıyor.
    private var pendingInstall: (() -> Void)?
    private var closeObserver: NSObjectProtocol?

    init(isPopoverShown: @escaping () -> Bool) {
        self.isPopoverShown = isPopoverShown
        super.init()

        #if DEBUG
        // Geliştirme derlemesi kendi kendini güncellemesin: yayınlanan sürüm
        // her zaman "daha yeni" görüneceği için her çalıştırmada üstüne
        // yayın sürümünü kurardı. Test için besleme ortam değişkeniyle veriliyor.
        guard ProcessInfo.processInfo.environment["CLAUDE_LIMIT_UPDATE_FEED"] != nil else { return }
        #endif

        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
        )
        self.controller = controller

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.installPendingIfAny() }
        }

        #if DEBUG
        if ProcessInfo.processInfo.environment["CLAUDE_LIMIT_UPDATE_CHECK_NOW"] == "1" {
            controller.updater.checkForUpdatesInBackground()
        }
        #endif
    }

    private func installPendingIfAny() {
        guard let install = pendingInstall else { return }
        pendingInstall = nil
        install()
    }

    /// Ayarlardaki düğme buraya bağlı: kullanıcı "şimdi denetle" dediğinde
    /// Sparkle'ın standart arayüzü (denetliyor → güncel / güncelleme var)
    /// açılıyor. Önce uygulama öne alınıyor (bkz. `AppActivation`), yoksa
    /// Sparkle penceresi arkada kalıp görünmeyebiliyor.
    func checkForUpdates() {
        guard let controller else { return }
        AppActivation.bringToFront()
        controller.checkForUpdates(nil)
    }

    /// Güncelleyici bu derlemede etkin mi (yayın derlemesinde her zaman).
    var isAvailable: Bool { controller != nil }
}

// Sparkle protokolü ana aktöre bağlı (`NS_SWIFT_UI_ACTOR`): yöntemler ana
// iş parçacığında çağrılıyor, sınıfın kendisi de ana aktörde.
extension AppUpdater: SPUUpdaterDelegate {
    #if DEBUG
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["CLAUDE_LIMIT_UPDATE_FEED"]
    }
    #endif

    #if DEBUG
    // Güncelleme akışının her adımı: uçtan uca testte nerede durduğunu görmek
    // için. Yayın derlemesinde yok.
    private func trace(_ line: String) {
        FileHandle.standardError.write(Data("[güncelleme] \(line)\n".utf8))
    }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        trace("besleme yüklendi: \(appcast.items.count) öge")
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        trace("geçerli güncelleme: \(item.displayVersionString) (\(item.versionString))")
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        trace("güncelleme yok: \(error.localizedDescription)")
    }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        trace("indiriliyor: \(request.url?.absoluteString ?? "-")")
    }
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        trace("indirildi")
    }
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        trace("indirme başarısız: \(error)")
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        trace("durdu: \(error)")
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        trace("kuruluyor: \(item.displayVersionString)")
    }
    #endif

    /// Sparkle güncellemeyi sessizce indirdi ve "uygulama kapanınca kurarım"
    /// diyor. Menü çubuğu uygulaması girişte açılıp aylarca kapanmadığı için
    /// bu pratikte hiç kurmamak demek; kurulum HEMEN yapılıyor.
    ///
    /// Tek istisna popover'ın açık olması: kullanıcı sayılara bakarken uygulama
    /// kapanıp açılırsa pencere gözünün önünden kaybolur. O durumda kurulum
    /// popover kapanana kadar bekliyor.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        #if DEBUG
        trace("kapanışta kurulacak → \(isPopoverShown() ? "popover kapanınca" : "hemen") kuruluyor")
        #endif
        if isPopoverShown() {
            pendingInstall = immediateInstallHandler
        } else {
            immediateInstallHandler()
        }
        return true
    }
}
