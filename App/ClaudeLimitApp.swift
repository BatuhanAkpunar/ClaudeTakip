import SwiftUI
import AppKit
import ServiceManagement
import LimitCore

@main
struct ClaudeLimitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Menü çubuğu ögesi AppKit tarafında kuruluyor. SwiftUI'ın en az bir
        // sahneye ihtiyacı var, Settings hem bu koşulu karşılıyor hem de
        // Cmd+, ile açılan native tercihler penceresini veriyor.
        // Ayarlar popover'ın ikinci sayfası. Buradaki sahne yalnızca SwiftUI'ın
        // "en az bir sahne" koşulunu karşılıyor; içi doluyken aynı ayarların
        // ikinci bir kopyası ortaya çıkıyor ve o kopya her çizimde ayrı bir
        // SQLite bağlantısı açıyordu.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore()
        let controller = StatusItemController(store: store)

        // Kota değiştiğinde menü çubuğu yeniden çizilir. Anlık görüntü aynıysa
        // denetleyici zaten çizimi atlıyor.
        store.onChange = { [weak controller] in controller?.render() }

        controller.install()

        self.store = store
        self.statusItem = controller

        #if DEBUG
        // Geliştirme kancaları yalnızca hata ayıklama derlemesinde. Yayınlanan
        // ikilide bir ortam değişkeniyle tetiklenebilen kod bırakmak gereksiz
        // bir yüzey.
          if ProcessInfo.processInfo.environment["CLAUDE_LIMIT_SELFTEST"] == "1" {
              // Veri katmanları yerleşsin, sonra davranış sınansın.
              DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                  SelfTest.run(store: store, controller: controller)
              }
          }

          if let path = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_RENDER"] {
              // Aktivite taraması bitsin ki saat grafiği dolu render edilsin.
              DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                  PreviewRenderer.render(store: store, to: path)
              }
          }

          if ProcessInfo.processInfo.environment["CLAUDE_LIMIT_SHOW_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                controller.showForMeasurement()
            }
        }

        if let path = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_RENDER_BATTERY"] {
            BatteryPreview.render(to: path)
        }
        if let path = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_RENDER_WALLET"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                PreviewRenderer.render(view: WalletGallery(), to: path)
            }
        }
        if let path = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_RENDER_SETTINGS"] {
              DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                  PreviewRenderer.render(view: SettingsPage(store: store) {}, to: path)
              }
          }
        #endif
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

#if DEBUG

/// Menü çubuğu ikonunu birkaç durumda, açık ve koyu çubukta önizler.
@MainActor
enum BatteryPreview {
    static func render(to path: String) {
        // (5 saatlik kullanım, haftalık kullanım, servis sağlıklı mı)
        let cases: [(Double, Double, Bool)] = [
            (8, 20, true), (46, 55, true), (78, 64, true), (92, 88, true), (100, 96, true), (30, 40, false),
        ]
        let tile = NSSize(width: 128, height: 34)
        let out = NSImage(size: NSSize(width: tile.width * CGFloat(cases.count), height: tile.height * 2))
        out.lockFocus()
        for (row, dark) in [(0, false), (1, true)] {
            for (col, item) in cases.enumerated() {
                let origin = NSPoint(x: CGFloat(col) * tile.width, y: CGFloat(row) * tile.height)
                (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
                NSRect(origin: origin, size: tile).fill()
                let snap = MenuBarSnapshot(
                    hasData: true, usedPercent: item.0, weeklyPercent: item.1,
                    countdownText: "3:54", isStale: false, serviceOK: item.2,
                    showPercent: true, showCountdown: true
                )
                // Tek görsel: demet + kutular + metin. Metin rengi menü çubuğu
                // tonuna göre (bu önizlemede satırın açık/koyu zeminine göre).
                let ink: NSColor = dark ? .white : .black
                let icon = MenuBarIconRenderer.colorImage(for: snap, dark: dark, ink: ink)
                icon.draw(at: NSPoint(x: origin.x + 6, y: origin.y + 6), from: .zero,
                          operation: .sourceOver, fraction: 1)
            }
        }
        out.unlockFocus()
        let tiff = out.tiffRepresentation!
        let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        try? png.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}

/// Yalnızca geliştirme aracı: popover içeriğini ekran dışında PNG'ye render eder.
///
/// Ekran görüntüsü almak için pencere açmak, aksesuar kipindeki bir uygulamada
/// odak yüzünden güvenilir çalışmıyordu. `ImageRenderer` görünümü hiç
/// göstermeden çiziyor, dolayısıyla sonuç her seferinde aynı.
@MainActor
enum PreviewRenderer {
    static func render(store: UsageStore, to path: String) {
        // Gerçek popover zeminini sistemden alıyor; ekran dışı render'da o zemin
        // olmadığı için yalnızca burada düz bir arka plan konuyor.
        render(view: PopoverRootView(store: store), to: path)
    }

    static func render(view: some View, to path: String) {
        // Koyu tema doğrulaması: RENDER_DARK ayarlıysa uygulama görünümü koyuya
        // sabitlenir. Palette dinamik NSColor kullandığından renkler
        // effectiveAppearance'a göre çözülür, colorScheme ortamı yetmez.
        let dark = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_RENDER_DARK"] == "1"
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        // Dinamik NSColor'lar rasterleştirme anındaki NSAppearance.current'a göre
        // çözülüyor; colorScheme ortamı SwiftUI-yerel renkler için.
        NSAppearance.current = appearance
        let content = view
            .background(Palette.previewBackdrop)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("render başarısız\n".utf8))
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("yazıldı: \(path)")
        } catch {
            FileHandle.standardError.write(Data("yazılamadı: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

#endif

/// Girişte başlatma. `SMAppService` macOS 13'ten beri doğru API.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Başarılıysa nil, değilse kullanıcıya gösterilecek mesaj döner.
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            // İmzasız veya Applications dışından çalışan derlemelerde sistem
            // kaydı reddedebiliyor; sessizce yutmak yerine söylüyoruz.
            return L.t("Sistem isteği reddetti: \(error.localizedDescription)", "The system refused: \(error.localizedDescription)")
        }
    }
}
