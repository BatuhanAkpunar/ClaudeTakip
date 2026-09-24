import SwiftUI
import AppKit
import LimitCore

@main
struct ClaudeLimitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Ayarlar popover'ın ikinci sayfası. Buradaki sahne yalnızca SwiftUI'ın
        // "en az bir sahne" koşulunu karşılıyor; içi doluyken aynı ayarların
        // ikinci bir kopyası ortaya çıkar ve o kopya her çizimde ayrı bir
        // SQLite bağlantısı açar.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItem: StatusItemController?
    private var updater: AppUpdater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore()
        let controller = StatusItemController(store: store)

        // Kota değiştiğinde menü çubuğu yeniden çizilir. Anlık görüntü aynıysa
        // denetleyici zaten çizimi atlıyor.
        store.onChange = { [weak controller] in controller?.render() }

        controller.install()

        self.store = store
        self.statusItem = controller
        let updater = AppUpdater { [weak controller] in controller?.isPopoverShown ?? false }
        self.updater = updater
        // Ayarlar sayfası güncelleyiciye buradan erişiyor.
        store.updatesAvailable = updater.isAvailable
        store.manualUpdateCheck = { [weak updater] in updater?.checkForUpdates() }

        #if DEBUG
        DebugHooks.install(store: store, controller: controller)
        #endif
    }

    /// Uygulama çalışırken Finder'dan yeniden açılırsa kaldırılmış menü
    /// çubuğu ögesi geri gelir; yoksa ulaşılacak hiçbir arayüz kalmıyor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.reveal()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
