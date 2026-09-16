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
    private let store: UsageStore
    private var lastSnapshot: MenuBarSnapshot?
    private var visibilityObserver: NSKeyValueObservation?


    init(store: UsageStore) {
        self.store = store
        super.init()
    }

    func install() {
        statusItem.autosaveName = "ClaudeLimitStatusItem"
        statusItem.behavior = .removalAllowed

        if let button = statusItem.button {
            // Varsayılan .scaleNone: sistem görseli ölçeklemez, 18x18 verdiğimiz gibi çizilir.
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseDown])
            button.setAccessibilityTitle("Claude Limit")

        }

        popover.behavior = .transient
        popover.animates = true

        let hosting = NSHostingController(rootView: PopoverRootView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // Uygulama aktifliği değiştiğinde cam katmanları yeniden sabitleniyor.
        // Odak kaybı/kazanımı AppKit'te malzemelerin tonunu değiştiren tek olay;
        // popover açıkken bu olduğunda renk gözle görülür şekilde oynuyordu.
        for name in [NSApplication.didResignActiveNotification,
                     NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pinNow() }
            }
        }

        // HIG: menü çubuğunda kalıp kalmayacağına uygulama değil kullanıcı karar verir.
        visibilityObserver = statusItem.observe(\.isVisible, options: [.new]) { _, change in
            guard let visible = change.newValue else { return }
            UserDefaults.standard.set(visible, forKey: "showInMenuBar")
        }

        render()
    }

    // MARK: - Çizim

    /// Kendi kendini testin okuduğu gözlemlenebilir durum: menü çubuğuna
    /// gerçekten ne yazıldığı ve ikonun konup konmadığı.
    /// Menü çubuğu artık metin başlığı kullanmıyor: geri sayım dahil her şey
    /// tek bir görselde, çünkü ögeler arasındaki boşluğu tek yerden vermek
    /// yarısını AppKit'in başlık yerleşimine bırakmaktan tutarlı.
    var debugHasImage: Bool { statusItem.button?.image != nil }
    var debugItemWidth: CGFloat { statusItem.length }

    func render() {
        let snapshot = store.menuBarSnapshot
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot

        guard let button = statusItem.button else { return }
        // Metin HER ZAMAN beyaz: menü çubuğu pratikte daima koyu/vibrant bir
        // zemin ve sistem saati de beyaz. Duvar kağıdı parlaklığından ton
        // türetmek denendi; koşulsuz beyaz hem daha öngörülebilir hem
        // yanındaki sistem ögeleriyle tutarlı.
        let dark = true
        let ink: NSColor = .white
        button.image = MenuBarIconRenderer.colorImage(for: snapshot, dark: dark, ink: ink)
        button.imagePosition = .imageOnly
        button.setAccessibilityValue(snapshot.spokenSummary)

        // `NSStatusBarButton`'da content-inset API'si yok, padding'in tek yolu length.
        // Genişlik anlık görüntüden hesaplanıyor: kapalı bilgiler için yer ayırmak
        // menü çubuğunda boş bir blok bırakıyordu.
        // Geri sayım da görselin içinde çiziliyor: ögeler arasındaki boşluğu
        // tek bir yerden vermek, yarısını AppKit'in başlık yerleşimine
        // bırakmaktan çok daha tutarlı. Genişlik doğrudan görselden.
        statusItem.length = ceil(MenuBarIconRenderer.width(for: snapshot)) + 8

    }

    // MARK: - Etkileşim

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }

        // Sağ tık menüsü kaldırıldı. Alt+tık hızlı yenileme kısayolu kalıyor.
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
            // Aktivasyon gösterimden ÖNCE: sonrasında yapıldığında popover bir
            // kare inaktif zeminle çizilip ardından aktife dönüyor ve renk
            // gözle görülür şekilde zıplıyor.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Native menü hissi için şart: açıkken öge vurgulu kalır.
            button.isHighlighted = true
            pinMaterialsActive()
        }
    }

    /// Cam yüzeyleri her zaman odaklıymış gibi göstermek.
    ///
    /// Vibrancy ve cam malzemeleri varsayılan olarak pencerenin aktiflik
    /// durumunu takip eder (`.followsWindowActiveState`) ve pencere key
    /// değilken soluklaşır. Popover, menü çubuğundan açıldığı için sık sık
    /// odak dışında kalıyor ve renk oynuyordu. `.active` sabitlenince malzeme
    /// odaktan bağımsız olarak tam tonunda kalıyor.
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

    #if DEBUG
    /// Ölçüm için: popover'ı tıklamadan açar, odak kaybında kapanmaz.
    func showForMeasurement() {
        guard let button = statusItem.button else { return }
        popover.behavior = .applicationDefined
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        button.isHighlighted = true
        pinMaterialsActive()

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

    private func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private func dumpMaterials(tag: String) {
        guard let window = popover.contentViewController?.view.window else {
            log("[\(tag)] popover penceresi YOK"); return
        }
        var found = 0
        func walk(_ v: NSView, _ depth: Int) {
            if let e = v as? NSVisualEffectView {
                found += 1
                let st = e.state == .active ? "active" : (e.state == .inactive ? "inactive" : "followsWindow")
                log("[\(tag)] \(String(repeating: "  ", count: depth))\(type(of: e)) material=\(e.material.rawValue) blending=\(e.blendingMode.rawValue) state=\(st)")
            }
            v.subviews.forEach { walk($0, depth + 1) }
        }
        let root = window.contentView?.superview ?? window.contentView
        if let root { walk(root, 0) }
        log("[\(tag)] toplam cam katman: \(found), pencere key mi: \(window.isKeyWindow), uygulama aktif mi: \(NSApp.isActive)")
    }
    #endif

    /// Popover PENCERESİNİN tamamındaki cam katmanlarını odaktan bağımsız kılar.
    ///
    /// Yalnızca içerik görünümünü gezmek yetmiyordu: popover'ın kendi zeminini
    /// AppKit çiziyor ve o katman içerik ağacının DIŞINDA, pencere çerçevesinde
    /// duruyor. Pencerenin kök görünümünden başlamak onu da kapsıyor.
    private func pinNow() {
        func pin(_ view: NSView) {
            if let effect = view as? NSVisualEffectView { effect.state = .active }
            view.subviews.forEach(pin)
        }
        guard let window = popover.contentViewController?.view.window else { return }
        // contentView'ın da üstüne çıkılıyor: çerçeve görünümü orada.
        if let frame = window.contentView?.superview { pin(frame) }
        else if let content = window.contentView { pin(content) }
    }

}
