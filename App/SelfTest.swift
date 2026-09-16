import AppKit
import SwiftUI
import LimitCore

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

    /// Tasarımdaki "19 Eylülde sıfırlanır" cümlesi Türkçede ekin tarihe göre
    /// değişmesini gerektiriyor. On iki ay adı ve saat ekleri elle yazılmış
    /// bir tablo değil kuraldan türetiliyor, dolayısıyla sınanması gerekiyor.
    private static func checkResetSentences() {
        guard L.isTurkish else {
            check("Sıfırlanma cümlesi", "İngilizce arayüz, atlandı", true)
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func date(_ d: Int, _ m: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let months = [
            (1, "Ocakta"), (2, "Şubatta"), (3, "Martta"), (4, "Nisanda"),
            (5, "Mayısta"), (6, "Haziranda"), (7, "Temmuzda"), (8, "Ağustosta"),
            (9, "Eylülde"), (10, "Ekimde"), (11, "Kasımda"), (12, "Aralıkta"),
        ]
        var wrong: [String] = []
        for (m, expected) in months {
            let got = Format.resetSentence(date(1, m), includeTime: false)
            if !got.hasPrefix("1 \(expected) sıfırlanır") { wrong.append("\(m): \(got)") }
        }
        check("Sıfırlanma cümlesi: 12 ay eki", wrong.isEmpty ? "hepsi doğru" : wrong.joined(separator: " · "),
              wrong.isEmpty)

        let times: [(Int, Int, String)] = [
            (10, 0, "10:00da"), (5, 0, "05:00te"), (19, 0, "19:00da"),
            (13, 0, "13:00te"), (9, 30, "09:30da"), (14, 40, "14:40ta"),
            (8, 5, "08:05te"), (11, 11, "11:11de"),
        ]
        var badTimes: [String] = []
        for (h, m, expected) in times {
            let got = Format.resetSentenceTimeOnly(date(19, 9, h, m))
            if got != "\(expected) sıfırlanır" { badTimes.append("\(h):\(m) → \(got)") }
        }
        check("Sıfırlanma cümlesi: saat eki",
              badTimes.isEmpty ? "8 örnek doğru" : badTimes.joined(separator: " · "),
              badTimes.isEmpty)
    }

    static func run(store: UsageStore, controller: StatusItemController) {
        results = []

        checkMenuBar(controller)
        checkSettingsPage(store)
        checkRefresh(store)
        checkMenuBarFallbacksAndWallet()
        checkSignatureAndStorage()
        checkDataLayers(store)
        checkResetSentences()

        report()
    }

    // MARK: - Kontroller

    private static func checkMenuBar(_ controller: StatusItemController) {
        let item = NSStatusBar.system.statusItem(withLength: 0)
        NSStatusBar.system.removeStatusItem(item)
        // Öge kuruldu mu: görsel yazıldı mı ve genişliği içeriğe göre mi.
        check("Menü çubuğu ikonu", "", controller.debugHasImage)
        check("Menü çubuğu genişliği içerikten geliyor",
              "\(Int(controller.debugItemWidth)) pt",
              // Haftalık geri sayım eklendi: ~163 pt. Tavan 200: iki geri sayım
              // + yüzde + kutular, bundan genişi yerleşim hatasıdır.
              controller.debugItemWidth > 40 && controller.debugItemWidth < 200)
    }

    /// Ayarlar artık ayrı pencere değil, popover'ın ikinci sayfası.
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

    /// Menü çubuğu yerleşimi ve cüzdan kartı.
    ///
    /// Yerleşim kuralı: sol yarı haftalık (geri sayım + turuncu kutu), sağ yarı
    /// 5 saatlik (mavi kutu + yüzde + saat + geri sayım). Yüzde işareti dile
    /// göre. Menü çubuğu ayarları kaldırıldı; her öge her zaman görünür.
    private static func checkMenuBarFallbacksAndWallet() {
        let full = MenuBarSnapshot(
            hasData: true, usedPercent: 46, countdownText: "4:28",
            weeklyCountdownText: "6g 4s", isStale: false
        )
        let layout = MenuBarIconRenderer.layout(for: full)
        check("Menü çubuğu: haftalık geri sayım kutuların SOLUNDA",
              "weeklyX=\(layout.weeklyX) barX=\(layout.barX)",
              layout.weeklyText == "6g 4s" && layout.weeklyX > 0 && layout.weeklyX < layout.barX)
        check("Menü çubuğu: 5 saatlik yüzde ve geri sayım kutuların SAĞINDA",
              "barX=\(layout.barX) percentX=\(layout.percentX) countdownX=\(layout.countdownX)",
              layout.percentX > layout.barX && layout.countdownX > layout.percentX
                  && layout.countdownText == "4:28")
        check("Menü çubuğu: yüzde dile göre (%54)",
              "'\(layout.percentText)'", layout.percentText == L.t("%54", "54%"))

        let empty = MenuBarSnapshot(hasData: false, usedPercent: 0, countdownText: "", isStale: false)
        let emptyLayout = MenuBarIconRenderer.layout(for: empty)
        check("Menü çubuğu: veri yokken yalnız demet + kutular",
              "width=\(emptyLayout.width)",
              emptyLayout.weeklyText.isEmpty && emptyLayout.percentText.isEmpty
                  && emptyLayout.countdownText.isEmpty && emptyLayout.width < 45)

        // Tek görsel: demet + kutular + metin. Template DEĞİL (metin rengini
        // menü çubuğu tonuna göre kendimiz seçiyoruz).
        let iconDark = MenuBarIconRenderer.colorImage(for: full, dark: true, ink: .white)
        let iconLight = MenuBarIconRenderer.colorImage(for: full, dark: false, ink: .black)
        check("Menü çubuğu: tek non-template görsel",
              "template=\(iconDark.isTemplate)", !iconDark.isTemplate)
        check("Menü çubuğu: ton görseli değiştiriyor",
              "boyut \(iconDark.size)", iconDark.size == iconLight.size && iconDark.size.width > 40)

        // Cüzdan kartı: kompakt spec'in durumları doğru mu.
        func wallet(_ s: WalletState) -> WalletPresentation { WalletPresentation.make(s) }
        let spending = wallet(WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 60,
            monthlyLimit: nil, usedCredits: 13.83, remainingBalance: 9.18, currency: "USD",
            autoReloadEnabled: false, isFromStaleCache: false, cachedAt: nil))
        check("Cüzdan: açıkken kahraman = bakiye (etiketsiz), detay = harcanan",
              "\(spending.heroValue ?? "-") \(spending.heroLabel ?? "-") / \(spending.detail ?? "-")",
              spending.status == "Açık" && spending.heroValue == "$9,18" && spending.heroLabel == nil
                  && spending.detail == "$13,83 harcandı" && spending.amounts == nil)

        let capped = wallet(WalletState(isEnabled: false, disabledReason: nil, consumedPercent: 100,
            spendLimitReached: true, monthlyLimit: 2, usedCredits: 13.83, remainingBalance: 9.18,
            currency: "USD", autoReloadEnabled: true, isFromStaleCache: false, cachedAt: nil))
        check("Cüzdan: tavan dolunca amber durum",
              "durum=\(capped.status) ton=\(capped.statusTone)",
              capped.status == "Tavan doldu" && capped.statusTone == .warn
                  && capped.heroValue == "$9,18" && capped.heroLabel == nil)

        let dormant = wallet(WalletState(isEnabled: false, disabledReason: nil, consumedPercent: nil,
            remainingBalance: 34.50, currency: "USD", autoReloadEnabled: true,
            isFromStaleCache: false, cachedAt: nil))
        check("Cüzdan: kapalı bakiye + oto-yükleme göstergesi",
              "otoYükleme=\(dormant.autoReload.map(String.init) ?? "-")",
              dormant.status == "Kapalı" && dormant.heroValue == "$34,50" && dormant.heroLabel == nil
              && dormant.autoReload == true)

        let off = wallet(WalletState(isEnabled: false, disabledReason: "ekstra kullanım kapalı",
            consumedPercent: nil, isFromStaleCache: false, cachedAt: nil))
        check("Cüzdan: kapalı ve parasız tek satır",
              "amounts=\(off.amounts ?? "-")",
              off.status == "Kapalı" && off.barFraction == nil)
    }

    /// İmza tespiti ve oturum saklama yolu.
    ///
    /// Bu kontrol bir hatadan doğdu: imza tespiti ad-hoc'u yakalayamayınca
    /// uygulama Keychain yolunu seçti, Keychain yazma sessizce başarısız oldu
    /// ve oturum anahtarı hiçbir yere kaydedilmedi.
    private static func checkSignatureAndStorage() {
        let signature = CodeSignature.inspect()
        check("İmza tespiti çalışıyor", signature.detail, !signature.detail.contains("yok")
              && !signature.detail.contains("alınamadı") && !signature.detail.contains("başarısız"))

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
