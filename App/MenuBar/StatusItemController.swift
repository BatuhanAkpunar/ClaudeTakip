import AppKit
import SwiftUI
import LimitCore

/// Menü çubuğu ögesinin sahibi.
///
/// `MenuBarExtra` yerine `NSStatusItem` kullanılmasının sebebi ölçülebilir:
/// `MenuBarExtra`'nın label'ı yalnızca `Text` ve `Image` çıkarıp gerisini sessizce
/// atıyor, ayrıca `statusItem.length`, `attributedTitle` ve `isHighlighted`
/// erişimi vermiyor. Genişlik zıplamasını önlemek bunların hepsini gerektiriyor.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    /// Güncelleyici, kurulumu kullanıcı popover'a bakarken yapmamak için soruyor.
    var isPopoverShown: Bool { popover.isShown }
    private let store: UsageStore
    private var lastSnapshot: MenuBarSnapshot?
    /// Aktiflik gözlemcilerinin belirteçleri. Denetleyici uygulama boyunca
    /// yaşıyor; belirteçler kaybolmasın diye tutuluyor.
    private var activationObservers: [NSObjectProtocol] = []

    /// Görselin sağına ve soluna dağılan toplam iç pay (pt).
    private static let itemPadding: CGFloat = 8

    init(store: UsageStore) {
        self.store = store
        super.init()
    }

    func install() {
        statusItem.autosaveName = "ClaudeLimitStatusItem"
        statusItem.behavior = .removalAllowed
        // Uygulamanın başka arayüzü yok: Cmd ile sürüklenip kaldırılan öge
        // `autosaveName` sayesinde gizli hatırlanıyor ve geri getirecek
        // hiçbir yol kalmıyordu. Her açılışta görünür yapılıyor; kullanıcı
        // yine kaldırabilir, uygulamayı yeniden açmak geri getirir.
        reveal()

        if let button = statusItem.button {
            // Varsayılan .scaleNone: sistem görseli ölçeklemez, verdiğimiz gibi çizilir: 22 pt yüksek, içerik genişliğinde.
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseDown])
            button.setAccessibilityTitle("Claude Takip")

        }

        popover.behavior = .transient
        popover.animates = true
        // Dışarı tıklayınca `.transient` popover'ı AppKit kapatıyor ve
        // `togglePopover` hiç çalışmıyor; vurgu kapanışta buradan kalkmalı.
        popover.delegate = self

        let hosting = NSHostingController(rootView: PopoverRootView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // Uygulama aktifliği değiştiğinde cam katmanları yeniden sabitleniyor.
        // Odak kaybı/kazanımı AppKit'te malzemelerin tonunu değiştiren tek olay;
        // popover açıkken bu olduğunda renk gözle görülür şekilde oynar.
        for name in [NSApplication.didResignActiveNotification,
                     NSApplication.didBecomeActiveNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pinNow() }
            }
            activationObservers.append(token)
        }

        render()
    }

    /// Kaldırılmış menü çubuğu ögesini geri getirir (açılış, yeniden açma).
    func reveal() {
        statusItem.isVisible = true
    }

    // MARK: - Çizim

    #if DEBUG
    /// SelfTest'in okuduğu gözlemlenebilir durum
    var debugHasImage: Bool { statusItem.button?.image != nil }
    var debugItemWidth: CGFloat { statusItem.length }
    #endif

    func render() {
        let snapshot = store.menuBarSnapshot
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot

        guard let button = statusItem.button else { return }
        button.image = MenuBarIconRenderer.colorImage(for: snapshot)
        button.imagePosition = .imageOnly
        button.setAccessibilityValue(snapshot.spokenSummary)

        // `NSStatusBarButton`'da content-inset API'si yok, padding'in tek yolu length.
        // Genişlik anlık görüntüden hesaplanıyor: kapalı bilgiler için yer ayırmak
        // menü çubuğunda boş bir blok bırakır. Genişlik doğrudan görselden.
        statusItem.length = ceil(MenuBarIconRenderer.width(for: snapshot)) + Self.itemPadding

    }

    // MARK: - Etkileşim

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }

        // Sağ tık menüsü yok. Alt+tık hızlı yenileme kısayolu.
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) {
            store.refreshQuota()
            // Kullanıcı elle tetikledi: soğuma atlanıyor.
            store.refreshActivity(force: true)
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            button.isHighlighted = false
        } else {
            store.refreshQuota()
            showPopover(from: button)
        }
    }

    /// Popover'ı gösterir: öne alma, gösterim, vurgu ve cam sabitleme bu sırayla.
    private func showPopover(from button: NSStatusBarButton) {
        // Aktivasyon gösterimden ÖNCE: sonrasında yapıldığında popover bir
        // kare inaktif zeminle çizilip ardından aktife dönüyor ve renk
        // gözle görülür şekilde zıplıyor.
        AppActivation.bringToFront()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        // Native menü hissi için şart: açıkken öge vurgulu kalır.
        button.isHighlighted = true
        pinMaterialsActive()
    }

    /// Cam yüzeyleri her zaman odaklıymış gibi göstermek.
    ///
    /// Vibrancy ve cam malzemeleri varsayılan olarak pencerenin aktiflik
    /// durumunu takip eder (`.followsWindowActiveState`) ve pencere key
    /// değilken soluklaşır. Popover, menü çubuğundan açıldığı için sık sık
    /// odak dışında kalır ve renk oynar. `.active` sabitlenince malzeme
    /// odaktan bağımsız olarak tam tonunda kalır.
    /// Saydamlığın TEK kaynağı popover'ın çerçeve malzemesi: ağaçta bizim
    /// çizdiğimiz hiçbir `NSVisualEffectView` yok, buradaki gezinti o çerçeve
    /// zeminini odaktan bağımsız kılıyor (bkz. `CardSurface`).
    private func pinMaterialsActive() {
        pinNow()
        // SwiftUI malzeme katmanlarını sunum sırasında oluşturuyor; ilk geçişte
        // hepsi henüz yerinde değil. Birkaç kare sonra tekrar geziliyor.
        for delay in [0.02, 0.08, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pinNow()
            }
        }
    }

    /// Popover PENCERESİNİN tamamındaki cam katmanlarını odaktan bağımsız kılar.
    ///
    /// Yalnızca içerik görünümünü gezmek yetmez: popover'ın kendi zeminini
    /// AppKit çiziyor ve o katman içerik ağacının DIŞINDA, pencere çerçevesinde
    /// duruyor. Pencerenin kök görünümünden başlamak onu da kapsıyor.
    private func pinNow() {
        forEachEffectView { effect, _ in effect.state = .active }
    }

    /// Popover penceresindeki her `NSVisualEffectView`'ı derinliğiyle gezer.
    private func forEachEffectView(_ body: (NSVisualEffectView, Int) -> Void) {
        guard let window = popover.contentViewController?.view.window else { return }
        func walk(_ view: NSView, _ depth: Int) {
            if let effect = view as? NSVisualEffectView { body(effect, depth) }
            for sub in view.subviews { walk(sub, depth + 1) }
        }
        // contentView'ın da üstüne çıkılıyor: çerçeve görünümü orada.
        if let root = window.contentView?.superview ?? window.contentView { walk(root, 0) }
    }
}

extension StatusItemController: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { statusItem.button?.isHighlighted = false }
    }
}

#if DEBUG
extension StatusItemController {
    /// Ölçüm için: popover'ı tıklamadan açar, odak kaybında kapanmaz.
    func showForMeasurement() {
        guard let button = statusItem.button else { return }
        popover.behavior = .applicationDefined
        showPopover(from: button)

        // Cam katmanlarının durumunu dök: hangisi odağı takip ediyor?
        for delay in [1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.dumpMaterials(tag: delay == 1.0 ? "AKTİF" : "ODAK KAYBI SONRASI")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSApp.hide(nil)
        }
    }

    fileprivate func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    fileprivate func dumpMaterials(tag: String) {
        guard let window = popover.contentViewController?.view.window else {
            log("[\(tag)] popover penceresi YOK"); return
        }
        var found = 0
        forEachEffectView { e, depth in
            found += 1
            let st = e.state == .active ? "active" : (e.state == .inactive ? "inactive" : "followsWindow")
            log("[\(tag)] \(String(repeating: "  ", count: depth))\(type(of: e)) material=\(e.material.rawValue) blending=\(e.blendingMode.rawValue) state=\(st)")
        }
        log("[\(tag)] toplam cam katman: \(found), pencere key mi: \(window.isKeyWindow), uygulama aktif mi: \(NSApp.isActive)")
    }
}
#endif
