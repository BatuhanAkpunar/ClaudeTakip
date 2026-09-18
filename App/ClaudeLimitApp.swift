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
        // usedPercent: kalan = 100 - kullanılan. Yeşilden kırmızıya tüm bandı
        // gezmek için birçok değer + servis kesintisi + bayat + veri yok.
        let cases: [(String, MenuBarSnapshot)] = [
            ("kalan 100", snap(used: 0)),
            ("kalan 85", snap(used: 15)),
            ("kalan 67", snap(used: 33)),
            ("kalan 50", snap(used: 50)),
            ("kalan 33", snap(used: 67)),
            ("kalan 20", snap(used: 80)),
            ("kalan 8", snap(used: 92)),
            ("kalan 0", snap(used: 100)),
            ("kesinti", snap(used: 40, serviceOK: false)),
            ("bayat", snap(used: 40, stale: true)),
            ("veri yok", MenuBarSnapshot(hasData: false, usedPercent: 0, countdownText: "", isStale: false)),
        ]
        // Menü çubuğu 22 pt; iki ölçekte çiziyoruz: 1× (gerçek boy) ve 3×
        // (okunurluk denetimi). Zemin koyu vibrant menü çubuğunu taklit ediyor.
        let scales: [(String, CGFloat)] = [("1x", 1), ("3x", 3)]
        let rowH: CGFloat = 40
        let colW: CGFloat = 150
        let labelH: CGFloat = 16
        let out = NSImage(size: NSSize(
            width: colW * CGFloat(cases.count),
            height: (rowH + labelH) * CGFloat(scales.count)
        ))
        out.lockFocus()
        let barBG = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        for (row, scale) in scales.enumerated() {
            for (col, item) in cases.enumerated() {
                let ox = CGFloat(col) * colW
                let oy = CGFloat(row) * (rowH + labelH)
                barBG.setFill()
                NSRect(x: ox, y: oy, width: colW, height: rowH).fill()
                let icon = MenuBarIconRenderer.colorImage(for: item.1, dark: true, ink: .white)
                let w = icon.size.width * scale.1, h = icon.size.height * scale.1
                icon.draw(in: NSRect(x: ox + 8, y: oy + (rowH - h) / 2, width: w, height: h),
                          from: .zero, operation: .sourceOver, fraction: 1)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                (item.0 as NSString).draw(at: NSPoint(x: ox + 8, y: oy + rowH), withAttributes: attrs)
            }
        }
        out.unlockFocus()
        let tiff = out.tiffRepresentation!
        let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        try? png.write(to: URL(fileURLWithPath: path))
        exit(0)
    }

    private static func snap(used: Double, serviceOK: Bool = true, stale: Bool = false) -> MenuBarSnapshot {
        MenuBarSnapshot(hasData: true, usedPercent: used, weeklyPercent: 0,
                        countdownText: "3:54", isStale: stale, serviceOK: serviceOK)
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
