import AppKit
import LimitCore

/// Menü çubuğu ikonu.
///
/// Soldan sağa: `[Claude demeti] [iki dikey kutu] [kalan %] [kum saati] 3:54`
/// Son parça (geri sayım) düğmenin başlığı olarak çiziliyor, gerisi bu görselde.
///
/// Kutular DOLULUK değil KALAN gösteriyor: çubuk kısaldıkça hakkın azalıyor,
/// yanındaki sayı da aynı yönde okunuyor. Sıra `[haftalık][5 saatlik][%]`:
/// sayı 5 saatlik pencereye ait olduğu için onun kutusuna komşu duruyor,
/// yakınlık hangi sayının hangi kutuya ait olduğunu söylüyor.
///
/// Claude demeti servis sağlıklıyken marka renginde, kesintide kırmızı.
enum MenuBarIconRenderer {
    /// Ögeler arasındaki TEK boşluk değeri. Hepsi aynı olsun diye tek yerden.
    private static let gap: CGFloat = 5
    private static let height: CGFloat = 22
    private static let markWidth: CGFloat = 15
    private static let barW: CGFloat = 5, barH: CGFloat = 16, barGap: CGFloat = 2.5
    private static let clockSize: CGFloat = 11

    /// Yerleşim, soldan sağa:
    ///
    ///     [Claude demeti] 6g 4s [7g kutusu][5s kutusu] %12 ⏱ 0:45
    ///
    /// Sol yarı haftalık, sağ yarı 5 saatlik: her metin kendi kutusuna komşu
    /// duruyor, yakınlık aidiyeti söylüyor. İki katman (renk / mürekkep) aynı
    /// koordinatları buradan alıyor; eskiden iki yerde ayrı ayrı toplanıyor ve
    /// birbirinden kayabiliyordu.
    struct Layout {
        var markX: CGFloat = 2
        var weeklyX: CGFloat = 0
        var weeklyText = ""
        var barX: CGFloat = 0
        var percentX: CGFloat = 0
        var percentText = ""
        var clockX: CGFloat = 0
        var countdownX: CGFloat = 0
        var countdownText = ""
        var width: CGFloat = 0
    }

    static func layout(for s: MenuBarSnapshot) -> Layout {
        var l = Layout()
        var x: CGFloat = l.markX + markWidth
        if s.hasData, !s.weeklyCountdownText.isEmpty {
            x += gap; l.weeklyX = x; l.weeklyText = s.weeklyCountdownText
            x += textWidth(l.weeklyText)
        }
        x += gap; l.barX = x; x += barW * 2 + barGap
        if s.hasData {
            x += gap; l.percentX = x; l.percentText = percentText(s)
            x += textWidth(l.percentText)
        }
        if s.hasData, !s.countdownText.isEmpty {
            x += gap; l.clockX = x; x += clockSize + 3
            l.countdownX = x; l.countdownText = s.countdownText
            x += textWidth(l.countdownText)
        }
        l.width = x + 3
        return l
    }

    static func width(for snapshot: MenuBarSnapshot) -> CGFloat { layout(for: snapshot).width }

    /// Yüzde işareti dile göre: Türkçede "%12", İngilizcede "12%".
    static func percentText(_ s: MenuBarSnapshot) -> String {
        L.t("%\(s.remainingPercent)", "\(s.remainingPercent)%")
    }

    /// macOS'un menü çubuğunda kullandığı fontun ta kendisi: saat, pil ve
    /// menü başlıkları bununla çiziliyor, bizimki de onlarla aynı ağırlıkta
    /// ve boyda görünsün. Tek ekleme sabit genişlikli rakamlar: geri sayım
    /// her saniye değiştiği için oranlı rakamlarda metin sağa sola oynuyordu.
    static var textFont: NSFont {
        let base = NSFont.menuBarFont(ofSize: 0)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]
        ])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: textFont]).width
    }

    /// Claude'un marka rengi (terracotta). Popover'daki `Palette.claudeOrange`
    /// ile aynı değer: haftalık pencerenin kimliği.
    private static let claudeOrange = NSColor(
        srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1
    )

    /// Popover'daki `Palette.accent` ile birebir aynı kural: pencere kendi
    /// renginde, %90'dan sonra kırmızı. Amber ara kademe yok; turuncu artık
    /// haftalığın kimliği, uyarı rengi olamaz.
    private static func windowColor(
        _ usedPercent: Double, base: NSColor, stale: Bool, ink: NSColor
    ) -> NSColor {
        if stale { return ink.withAlphaComponent(0.35) }
        if usedPercent >= 90 { return .systemRed }
        return base
    }

    /// 5 saatlik pencerenin rengi (#2A78D6), koyu çubukta bir tık açık.
    private static func fiveHourBase(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0x5B / 255, green: 0x9E / 255, blue: 0xEE / 255, alpha: 1)
            : NSColor(srgbRed: 0x2A / 255, green: 0x78 / 255, blue: 0xD6 / 255, alpha: 1)
    }

    /// Renkli katman: Claude demeti + iki kutunun dolgusu.
    ///
    /// Bilerek `isTemplate = false`: bu ögelerin rengi bilgi taşıyor (marka
    /// rengi, kullanım şiddeti), sabit kalmalı. Apple'ın pil simgesinin kritik
    /// durumda kırmızıya dönmesiyle aynı mantık: renk template'in dışında.
    /// Tüm ikon TEK non-template görselde: demet + kutular + metin.
    ///
    /// Metin `ink` renginde çiziliyor; bu renk menü çubuğunun GERÇEK tonuna
    /// göre (duvar kağıdı parlaklığı) çağıran tarafça seçiliyor. Template
    /// yolu denendi ama `NSStatusBarButton.image` bizim kurulumumuzda menü
    /// çubuğu tonuna boyanmıyordu: sistem Açık modda koyu duvar kağıdı olan
    /// kullanıcıda metin siyah kalıyor, yanındaki sistem saati beyazken.
    static func colorImage(for snapshot: MenuBarSnapshot, dark: Bool, ink: NSColor) -> NSImage {
        let stale = snapshot.isStale
        let l = layout(for: snapshot)
        let canvas = NSSize(width: l.width, height: height)

        let image = NSImage(size: canvas, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let mid = height / 2

            drawClaudeMark(
                center: CGPoint(x: l.markX + 7.5, y: mid), radius: 7.2,
                color: snapshot.serviceOK ? claudeOrange : .systemRed,
                stale: stale, in: ctx
            )

            // İki dikey kutu: sol haftalık (turuncu), sağ 5 saatlik (mavi).
            let barY = (height - barH) / 2
            drawBar(
                rect: CGRect(x: l.barX, y: barY, width: barW, height: barH),
                remaining: snapshot.hasData ? 1 - min(max(snapshot.weeklyPercent / 100, 0), 1) : 0,
                color: windowColor(snapshot.weeklyPercent, base: claudeOrange, stale: stale, ink: ink),
                track: ink.withAlphaComponent(stale ? 0.10 : 0.16), in: ctx
            )
            drawBar(
                rect: CGRect(x: l.barX + barW + barGap, y: barY, width: barW, height: barH),
                remaining: snapshot.hasData ? 1 - min(max(snapshot.usedPercent / 100, 0), 1) : 0,
                color: windowColor(snapshot.usedPercent, base: fiveHourBase(dark: dark), stale: stale, ink: ink),
                track: ink.withAlphaComponent(stale ? 0.10 : 0.16), in: ctx
            )

            // Metin: haftalık geri sayım (sol), 5 saatlik yüzde + saat + geri
            // sayım (sağ). Renk çağıranın belirlediği menü çubuğu tonu.
            let textColor = ink.withAlphaComponent(stale ? 0.5 : 1)
            if !l.weeklyText.isEmpty {
                draw(l.weeklyText, at: CGPoint(x: l.weeklyX, y: mid), color: textColor)
            }
            if !l.percentText.isEmpty {
                draw(l.percentText, at: CGPoint(x: l.percentX, y: mid), color: textColor)
            }
            if !l.countdownText.isEmpty {
                drawSymbol("clock", at: CGPoint(x: l.clockX, y: mid), size: clockSize, color: textColor)
                draw(l.countdownText, at: CGPoint(x: l.countdownX, y: mid), color: textColor)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Menü çubuğu metni: eşit genişlikli sistem fontu, dikeyde ortalı.
    private static func draw(_ text: String, at origin: CGPoint, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: origin.x, y: origin.y - size.height / 2), withAttributes: attrs)
    }

    // MARK: - Parçalar

    /// Kalanı alttan dolduran dikey kutu.
    private static func drawBar(
        rect: CGRect, remaining: Double, color: NSColor, track: NSColor, in ctx: CGContext
    ) {
        // Köşeler neredeyse keskin. Yarıçap genişliğin yarısıyken kutunun üstü
        // yarım daireye dönüyor ve doluluk seviyesi okunmuyordu; kutu artık
        // kutu gibi görünüyor, üst kenarı düz bir çizgi.
        let radius: CGFloat = 1.5
        ctx.setFillColor(track.cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()

        let fraction = min(max(remaining, 0), 1)
        guard fraction > 0.001 else { return }
        // Çok az kalanda bile görünür bir iz kalmalı, yoksa "veri yok" sanılıyor.
        let filled = max(rect.width, rect.height * fraction)
        let fill = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: filled)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: fill, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Claude'un ışın demeti.
    ///
    /// Gerçek simge yuvarlak uçlu ÇİZGİLERDEN değil, KAMALARDAN oluşuyor:
    /// her ışın merkeze doğru genişliyor, uca doğru daralıyor ve ucu düz
    /// kesilmiş. Işınlar merkezde birleşip dolu bir çekirdek oluşturuyor,
    /// boyları da belirgin biçimde düzensiz. Önceki çizim eşit kalınlıkta ince
    /// çizgilerdi ve bambaşka bir şeye benziyordu.
    ///
    /// Ölçüler kurulu Claude uygulamasının kendi ikonu büyütülerek çıkarıldı;
    /// dosya kopyalanmıyor, aynı geometri yeniden çiziliyor.
    private static func drawClaudeMark(
        center: CGPoint, radius: CGFloat, color: NSColor, stale: Bool, in ctx: CGContext
    ) {
        // Işın boyları: markanın karakteri bu düzensizlikte.
        let lengths: [CGFloat] = [1.0, 0.70, 0.94, 0.78, 1.0, 0.66, 0.90, 0.74, 0.98, 0.68, 0.86]
        let count = lengths.count
        let baseHalf = radius * 0.155    // merkezdeki yarı genişlik
        let tipHalf = radius * 0.052     // uçtaki yarı genişlik

        ctx.saveGState()
        ctx.setFillColor(color.withAlphaComponent(stale ? 0.45 : 1).cgColor)

        for (index, factor) in lengths.enumerated() {
            let angle = Double.pi / 2 - Double(index) / Double(count) * 2 * Double.pi
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let perp = CGPoint(x: -dir.y, y: dir.x)
            let tip = radius * factor
            // Uç düz kesik: köşeler hafif pahlı, kristal görünümü buradan geliyor.
            let chamfer = tipHalf * 0.9

            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x + perp.x * baseHalf, y: center.y + perp.y * baseHalf))
            path.addLine(to: CGPoint(
                x: center.x + dir.x * (tip - chamfer) + perp.x * tipHalf,
                y: center.y + dir.y * (tip - chamfer) + perp.y * tipHalf))
            path.addLine(to: CGPoint(
                x: center.x + dir.x * tip + perp.x * tipHalf * 0.45,
                y: center.y + dir.y * tip + perp.y * tipHalf * 0.45))
            path.addLine(to: CGPoint(
                x: center.x + dir.x * tip - perp.x * tipHalf * 0.45,
                y: center.y + dir.y * tip - perp.y * tipHalf * 0.45))
            path.addLine(to: CGPoint(
                x: center.x + dir.x * (tip - chamfer) - perp.x * tipHalf,
                y: center.y + dir.y * (tip - chamfer) - perp.y * tipHalf))
            path.addLine(to: CGPoint(x: center.x - perp.x * baseHalf, y: center.y - perp.y * baseHalf))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }

        // Çekirdek: kamalar merkezde birleşince kalan küçük boşlukları kapatıyor.
        ctx.addArc(center: center, radius: radius * 0.20, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// SF Symbol çizimi. Kum saati için elle çizim yerine sistem simgesi:
    /// menü çubuğunun geri kalanıyla aynı optik ağırlıkta oluyor.
    private static func drawSymbol(_ name: String, at center: CGPoint, size: CGFloat, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            color.set()
            rect.fill(using: .sourceOver)
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        tinted.draw(
            at: NSPoint(x: center.x, y: center.y - symbol.size.height / 2),
            from: .zero, operation: .sourceOver, fraction: 1
        )
    }
}
