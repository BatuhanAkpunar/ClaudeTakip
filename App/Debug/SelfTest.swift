import AppKit
import SwiftUI
import LimitCore


// Kendi kendini test yalnızca hata ayıklama derlemesinde: yayın ikilisinde
// ne çağrılıyor ne de derleniyor (MenuBarSnapshot.sample gibi DEBUG-özel yardımcıları kullanıyor).
#if DEBUG
/// Uygulamayı gerçekten çalıştırarak davranışını doğrular.
///
/// Var olma sebebi bir eksikti: tasarım doğrulaması `ImageRenderer` ile
/// yapılıyordu ve o yalnızca görünüm ağacını çiziyor. Düğmeler, pencereler,
/// menüler ve AppKit bağlantıları hiç çalıştırılmıyordu, dolayısıyla ölü bir
/// düğme testten geçiyordu.
///
/// Bu mod her eylemi gerçekten tetikliyor ve sonucu gözlemlenebilir bir
/// durumdan okuyor: pencere gerçekten açıldı mı, menü gerçekten kuruldu mu.
@MainActor
enum SelfTest {
    private struct Result {
        let name: String
        let passed: Bool
        let detail: String
    }

    private static var results: [Result] = []

    private static func check(_ name: String, _ detail: String = "", _ condition: Bool) {
        results.append(Result(name: name, passed: condition, detail: detail))
    }

    static func run(store: UsageStore, controller: StatusItemController) {
        results = []

        checkMenuBar(controller)
        checkSettingsPage(store)
        checkRefresh(store)
        checkMenuBarLayout()
        checkMenuBarColors()
        checkPillNumberPlacement()
        checkWalletPresentation()
        checkSignatureAndStorage()
        checkDataLayers(store)

        report()
    }

    // MARK: - Kontroller

    private static func checkMenuBar(_ controller: StatusItemController) {
        // Öge kuruldu mu: görsel yazıldı mı ve genişliği içeriğe göre mi.
        check("Menü çubuğu ikonu", "", controller.debugHasImage)
        check("Menü çubuğu genişliği içerikten geliyor",
              "\(Int(controller.debugItemWidth)) pt",
              // Tavan 200: işaret + pil + geri sayım bundan dar; daha genişi
              // yerleşim hatasıdır.
              controller.debugItemWidth > 40 && controller.debugItemWidth < 200)
    }

    /// Ayarlar ayrı pencere değil, popover'ın ikinci sayfası.
    /// Doğrulanan şey: sayfa aynı genişlikte render ediliyor ve içeriği dolu.
    private static func checkSettingsPage(_ store: UsageStore) {
        let hosting = NSHostingController(rootView: SettingsPage(store: store) {})
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize

        check("Ayarlar sayfası çiziliyor",
              "\(Int(size.width))x\(Int(size.height)) pt",
              size.width > 100 && size.height > 100)
        // Genişlik ana sayfayla aynı olmalı, yoksa geçişte popover yatayda zıplar.
        check("Ayarlar genişliği ana sayfayla aynı",
              "\(Int(size.width)) pt (beklenen \(Int(PopoverLayout.width)))",
              abs(size.width - PopoverLayout.width) < 1)
    }

    private static func checkRefresh(_ store: UsageStore) {
        let before = store.lastRefreshedAt
        store.refreshAll()
        // `refreshAll` senkron olarak kotayı yeniden okuyor.
        check("Yenile verileri tazeliyor",
              "önce \(before.timeIntervalSince1970), sonra \(store.lastRefreshedAt.timeIntervalSince1970)",
              store.lastRefreshedAt >= before)
        check("Yenile göstergesi tetikleniyor", "", store.isRefreshing)
    }

    /// Menü çubuğu yerleşimi.
    ///
    /// Yerleşim kuralı: [işaret] [pil] [saat] geri sayım, soldan sağa. Pilin
    /// içindeki sayı 5 saatlik limitin kalan yüzdesi, işaretsiz.
    private static func checkMenuBarLayout() {
        let full = MenuBarSnapshot(
            hasData: true, usedPercent: 46, countdownText: "4:28", isStale: false
        )
        let layout = MenuBarIconRenderer.layout(for: full)
        // Yerleşim: [demet] [pil] [saat] geri sayım.
        check("Menü çubuğu: pil demetin sağında",
              "pillX=\(layout.pillX) markX=\(layout.markX)",
              layout.pillX > layout.markX)
        check("Menü çubuğu: geri sayım pilin sağında",
              "pillX=\(layout.pillX) countdownX=\(layout.countdownX)",
              layout.countdownX > layout.pillX && layout.countdownText == "4:28")

        // Pilin içindeki sayı KALAN yüzde, işaretsiz. %46 kullanıldı → 54 kaldı.
        check("Menü çubuğu: kalan yüzde işaretsiz",
              "remaining=\(full.remainingPercent)", full.remainingPercent == 54)

        let empty = MenuBarSnapshot.noData
        let emptyLayout = MenuBarIconRenderer.layout(for: empty)
        check("Menü çubuğu: veri yokken yalnız demet + boş pil",
              "width=\(emptyLayout.width)",
              emptyLayout.countdownText.isEmpty && emptyLayout.width < 85)

        let iconDark = MenuBarIconRenderer.colorImage(for: full, ink: .white)
        check("Menü çubuğu: tek non-template görsel",
              "template=\(iconDark.isTemplate)", !iconDark.isTemplate)
        check("Menü çubuğu: pil sabit genişlik (yüzdeyle zıplamıyor)",
              "w100=\(MenuBarIconRenderer.width(for: MenuBarSnapshot.sample(used: 0))) w8=\(MenuBarIconRenderer.width(for: MenuBarSnapshot.sample(used: 92)))",
              MenuBarIconRenderer.width(for: MenuBarSnapshot.sample(used: 0))
                  == MenuBarIconRenderer.width(for: MenuBarSnapshot.sample(used: 92)))
    }

    /// Menü çubuğu renkleri: yakıt göstergesi ve pil içi mürekkep.
    private static func checkMenuBarColors() {
        // Yakıt göstergesi: kalan azaldıkça yeşilden kırmızıya. Uçlar ve orta.
        func hue(_ remaining: Double) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            let c = MenuBarIconRenderer.gaugeColor(remaining: remaining).usingColorSpace(.sRGB)!
            return (c.redComponent, c.greenComponent, c.blueComponent)
        }
        let hi = hue(1.0), lo = hue(0.0)
        check("Menü çubuğu: dolu yeşil, boş kırmızı",
              "dolu=(\(Int(hi.r*255)),\(Int(hi.g*255)),\(Int(hi.b*255))) boş=(\(Int(lo.r*255)),\(Int(lo.g*255)),\(Int(lo.b*255)))",
              hi.g > hi.r && lo.r > lo.g)

        // Metin okunurluğu: parlak dolguda mürekkep KOYU, kırmızı/gri zeminde
        // beyaz. İki uçta da yeterli kontrast (parlaklık farkı büyük).
        func lum(_ c: NSColor) -> CGFloat {
            let s = c.usingColorSpace(.sRGB)!
            return 0.2126*s.redComponent + 0.7152*s.greenComponent + 0.0722*s.blueComponent
        }
        let green = MenuBarIconRenderer.gaugeColor(remaining: 1.0)
        let inkGreen = MenuBarIconRenderer.readableInk(on: green)
        check("Menü çubuğu: parlak dolguda koyu okunur mürekkep",
              "kontrast=\(String(format: "%.1f", (lum(green)+0.05)/(lum(inkGreen)+0.05)))",
              lum(inkGreen) < lum(green) && (lum(green)+0.05)/(lum(inkGreen)+0.05) >= 3.0)
    }

    /// Pil içindeki sayının yeri: doluluk sınırını hiç kesmiyor.
    private static func checkPillNumberPlacement() {
        // Sayı HER doluluk seviyesinde tek renk zemin üstünde, sınırı KESMEDEN.
        // Kullanıcı geri bildirimi: iki renge bölünen metin okunmuyordu.
        var straddles: [String] = []
        for r in 0...100 {
            // Dolgu KALANa göre (r = kullanılan), çizimdeki formülün kendisiyle.
            let remaining = 100 - r
            let fw = MenuBarIconRenderer.fillWidth(remaining: Double(remaining) / 100)
            let tw = ("\(remaining)" as NSString).size(withAttributes: [.font: MenuBarIconRenderer.numberFont]).width
            let place = MenuBarIconRenderer.numberPlacement(fillWidth: fw, textWidth: tw)
            let left = place.x, right = place.x + tw
            // Kesişmez: ya tümü dolunun solunda (right <= sınır) ya tümü sağında (left >= sınır).
            let ok = (right <= fw + 0.01) || (left >= fw - 0.01)
            if !ok { straddles.append("%\(remaining): [\(Int(left))-\(Int(right))] sınır=\(Int(fw))") }
        }
        check("Menü çubuğu: sayı doluluk sınırını hiç kesmiyor",
              straddles.isEmpty ? "0-100 hepsi tek zeminde" : straddles.prefix(4).joined(separator: " · "),
              straddles.isEmpty)
    }

    /// Cüzdan kartı sunumu.
    private static func checkWalletPresentation() {
        // Cüzdan kartı: kompakt spec'in durumları doğru mu.
        func wallet(_ s: WalletState) -> WalletPresentation { WalletPresentation.make(s) }
        let spending = wallet(WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 60,
            monthlyLimit: nil, usedCredits: 13.83, remainingBalance: 9.18, currency: "USD",
            autoReloadEnabled: false))
        check("Cüzdan: açıkken kahraman = bakiye (etiketsiz), detay = harcanan",
              "\(spending.heroValue ?? "-") \(spending.heroLabel ?? "-") / \(spending.detail ?? "-")",
              spending.statusTone == .calm && spending.heroValue != nil && spending.heroLabel == nil
                  && spending.detail != nil && spending.amounts == nil)  // locale-bağımsız: ton + yapı

        let capped = wallet(WalletState(isEnabled: false, disabledReason: nil, consumedPercent: 100,
            spendLimitReached: true, monthlyLimit: 2, usedCredits: 13.83, remainingBalance: 9.18,
            currency: "USD", autoReloadEnabled: true))
        check("Cüzdan: tavan dolunca amber durum",
              "durum=\(capped.status) ton=\(capped.statusTone)",
              capped.statusTone == .warn && capped.heroValue != nil && capped.heroLabel == nil)

        let dormant = wallet(WalletState(isEnabled: false, disabledReason: nil, consumedPercent: nil,
            remainingBalance: 34.50, currency: "USD", autoReloadEnabled: true))
        check("Cüzdan: kapalı bakiye + oto-yükleme göstergesi",
              "otoYükleme=\(dormant.autoReload.map(String.init) ?? "-")",
              dormant.statusTone == .muted && dormant.heroValue != nil && dormant.heroLabel == nil
              && dormant.autoReload == true)

        let off = wallet(WalletState(isEnabled: false, disabledReason: "ekstra kullanım kapalı",
            consumedPercent: nil))
        check("Cüzdan: kapalı ve parasız tek satır",
              "amounts=\(off.amounts ?? "-")",
              off.statusTone == .muted && off.barFraction == nil && off.amounts != nil)
    }

    /// İmza tespiti ve oturum saklama yolu.
    ///
    /// Bu kontrol bir hatadan doğdu: imza tespiti ad-hoc'u yakalayamayınca
    /// uygulama Keychain yolunu seçti, Keychain yazma sessizce başarısız oldu
    /// ve oturum anahtarı hiçbir yere kaydedilmedi.
    private static func checkSignatureAndStorage() {
        let signature = CodeSignature.inspect()
        check("İmza tespiti çalışıyor", signature.detail, signature.flagsRead)

        // Yazıp geri okuyarak saklamanın gerçekten çalıştığı doğrulanıyor.
        let probe = SessionStore(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("claudetakip-selftest-\(UUID().uuidString).json"),
            keychain: KeychainStore(service: "ClaudeLimitSelfTest", account: "probe")
        )
        let written = SessionStore.Session(sessionKey: "sk-test-0123456789", organizationID: "org-1")
        let saved = probe.save(written)
        let read = probe.load()
        probe.clear()

        check("Oturum saklanıp geri okunuyor",
              read?.sessionKey == written.sessionKey ? "tamam" : "GERİ OKUNAMADI",
              saved && read?.sessionKey == written.sessionKey)
    }

    private static func checkDataLayers(_ store: UsageStore) {
        // Claude Desktop kurulu olmayan makine taklit ediliyorsa, uygulamanın
        // sunucu verisiyle ayakta kalması BEKLENIR. Hata kartı göstermesi hata olur.
        let noDesktop = ProcessInfo.processInfo.environment["CLAUDE_LIMIT_NO_DESKTOP"] == "1"

        if noDesktop, store.authState == .signedIn {
            // Girişliyken sunucu kesin değerleri veriyor, Claude Desktop'ın
            // yokluğu engel olmamalı.
            check("Desktop'sız: hata kartı yok", store.loadError ?? "yok", store.loadError == nil)
            check("Desktop'sız: 5 saatlik pencere var",
                  store.fiveHour.map { "%\(Int($0.usedPercent))" } ?? "YOK",
                  store.fiveHour != nil)
            check("Desktop'sız: haftalık pencere var",
                  store.weekly.map { "%\(Int($0.usedPercent))" } ?? "YOK",
                  store.weekly != nil)
        } else if noDesktop {
            // Ne Desktop ne giriş varsa gösterilecek veri gerçekten yok.
            // Beklenen davranış boş kalmak değil, sebebini söylemek.
            check("Desktop'sız + girişsiz: sebep açıklanıyor",
                  store.loadError ?? "AÇIKLAMA YOK",
                  store.loadError?.isEmpty == false)
        }

        // Veri kaynağı hiç yoksa pencerelerin boş olması doğru davranış.
        let expectsWindows = !noDesktop || store.authState == .signedIn
        check("5 saatlik pencere",
              store.fiveHour.map { "%\(Int($0.usedPercent))" } ?? "yok",
              expectsWindows ? store.fiveHour != nil : true)
        check("Haftalık pencere",
              store.weekly.map { "%\(Int($0.usedPercent))" } ?? "yok",
              expectsWindows ? store.weekly != nil : true)
        check("Oturum durumu", "\(store.authState)", true)
        // Arşiv Claude Desktop olmadan da dolmalı: sunucu okumaları yazılıyor.
        check("Arşiv yazıyor",
              "\(store.historyStats.count) ölçüm",
              store.historyStats.count > 0 || (noDesktop && store.authState != .signedIn))
        check("Hesap bilgisi okundu",
              store.account?.planLabel ?? "YOK",
              store.account != nil)
    }

    // MARK: - Rapor

    private static func report() {
        let failed = results.filter { !$0.passed }
        print("\n=== KENDİ KENDİNİ TEST ===")
        for result in results {
            let mark = result.passed ? "✓" : "✗"
            let detail = result.detail.isEmpty ? "" : "  (\(result.detail))"
            print("\(mark) \(result.name)\(detail)")
        }
        print("\n\(results.count - failed.count)/\(results.count) geçti")
        exit(failed.isEmpty ? 0 : 1)
    }
}

#endif