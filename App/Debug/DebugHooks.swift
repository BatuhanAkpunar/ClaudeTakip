import SwiftUI
import AppKit
import LimitCore

#if DEBUG

/// Geliştirme kancaları: ortam değişkenleriyle tetiklenen öz sınama ve önizleme çıktıları.
@MainActor
enum DebugHooks {
    static func install(store: UsageStore, controller: StatusItemController) {
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
    }
}

#endif
