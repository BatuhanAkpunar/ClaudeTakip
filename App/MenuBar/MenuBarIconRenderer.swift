import AppKit
import LimitCore

/// Menü çubuğu ikonu.
///
/// Soldan sağa: `[Claude demeti] [pil] [kum saati] 0:45`
///
/// Haftalık pencere menü çubuğundan çıkarıldı (kullanıcı isteği): tek bir
/// pencereye odaklanınca ikon hem sakin hem net. Kalan bilgi 5 saatlik pencere:
///
///   - **Pil** (macOS 26 tarzı yatay kapsül): kalan kotayı hem DOLULUKLA hem
///     içine yazılı SAYIYLA gösteriyor. Kalan azaldıkça renk yeşilden kırmızıya
///     kayıyor (yakıt göstergesi mantığı); pil bir "ne kadar hakkım var" sorusu,
///     kotanın kimlik rengi (mavi) değil sağlık rengi doğru cevap.
///   - **Kum saati + geri sayım**: 5 saatlik pencerenin ne zaman sıfırlanacağı.
///
/// Claude demeti servis sağlıklıyken marka renginde, kesintide kırmızı.
enum MenuBarIconRenderer {
    /// Ögeler arasındaki TEK boşluk değeri.
    private static let gap: CGFloat = 5
    private static let height: CGFloat = 22
    private static let markWidth: CGFloat = 15

    /// Pil ölçüleri. Yükseklik menü çubuğunda olabildiğince yüksek: 22 pt
    /// tuvalde 17 pt kapsül, üstte altta 2,5 pt pay. Apple'ın pil simgesinden
    /// belirgin biçimde daha dolgun, ama kenara değmeyecek kadar paylı.
    /// Genişlik SABİT: "100" en geniş sayı (24,3 pt) iki yandan payla sığıyor;
    /// sabit olması menü çubuğu ögesinin yüzde değiştikçe zıplamasını önlüyor.
    private static let pillHeight: CGFloat = 17
    private static let pillWidth: CGFloat = 38
    /// Sayının kapsül uçlarının yuvarlağına girmemesi için yatay iç pay.
    private static let pillTextInset: CGFloat = 5
    private static let clockSize: CGFloat = 11

    /// Pilin içindeki sayı: menü çubuğu fontuyla aynı boy değil, biraz daha
    /// küçük ama yarı kalın; 17 pt kapsülde büyük harf yüksekliği ~8,5 pt, yani
    /// kapsülün yarısı. Eş genişlikli rakam: sayı değişince metin oynamıyor.
    static var numberFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    }

    struct Layout {
        var markX: CGFloat = 2
        var pillX: CGFloat = 0
        var clockX: CGFloat = 0
        var countdownX: CGFloat = 0
        var countdownText = ""
        var width: CGFloat = 0
    }

    static func layout(for s: MenuBarSnapshot) -> Layout {
        var l = Layout()
        var x: CGFloat = l.markX + markWidth
        x += gap; l.pillX = x; x += pillWidth
        if s.hasData, s.showCountdown, !s.countdownText.isEmpty {
            x += gap; l.clockX = x; x += clockSize + 3
            l.countdownX = x; l.countdownText = s.countdownText
            x += textWidth(l.countdownText)
        }
        l.width = x + 3
        return l
    }

    static func width(for snapshot: MenuBarSnapshot) -> CGFloat { layout(for: snapshot).width }

    #if DEBUG
    /// Yalnızca self-test: verilen kullanım için tam bir anlık görüntü.
    static func testSnap(used: Double) -> MenuBarSnapshot {
        MenuBarSnapshot(hasData: true, usedPercent: used, countdownText: "3:54", isStale: false)
    }
    #endif

    /// Geri sayım metni için menü çubuğu fontu (eş genişlikli rakam), pilin
    /// yanındaki saatle aynı optik ağırlıkta.
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

    // MARK: - Renkler

    private static func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// Claude'un marka rengi (terracotta). Popover'daki `Palette.claudeOrange`.
    private static let claudeOrange = srgb(0xD9, 0x77, 0x57)

    /// Yakıt göstergesi: KALAN oranına göre yeşilden kırmızıya. Kalan azaldıkça
    /// renk ısınıyor. Duraklar Apple'ın canlı sistem renkleri (koyu menü
    /// çubuğunda parlak okunuyor). Ara değerler sRGB'de doğrusal karışıyor.
    private static let gaugeStops: [(Double, NSColor)] = [
        (0.00, srgb(255, 69, 58)),    // kırmızı
        (0.25, srgb(255, 159, 10)),   // turuncu
        (0.50, srgb(255, 214, 10)),   // sarı
        (1.00, srgb(48, 209, 88)),    // yeşil
    ]

    static func gaugeColor(remaining: Double) -> NSColor {
        let t = min(max(remaining, 0), 1)
        var lower = gaugeStops[0], upper = gaugeStops[gaugeStops.count - 1]
        for i in 1..<gaugeStops.count where gaugeStops[i].0 >= t {
            lower = gaugeStops[i - 1]; upper = gaugeStops[i]; break
        }
        let span = upper.0 - lower.0
        let f = span > 0 ? (t - lower.0) / span : 0
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * f }
        return NSColor(
            srgbRed: mix(lower.1.redComponent, upper.1.redComponent),
            green: mix(lower.1.greenComponent, upper.1.greenComponent),
            blue: mix(lower.1.blueComponent, upper.1.blueComponent),
            alpha: 1
        )
    }

    /// Basit göreli parlaklık: hangi mürekkebin (koyu/açık) daha okunur olacağına
    /// karar vermek için yeter.
    private static func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB) ?? c
        return 0.2126 * s.redComponent + 0.7152 * s.greenComponent + 0.0722 * s.blueComponent
    }

    /// Bir zemin renginin üstünde EN OKUNUR mürekkep.
    ///
    /// Parlak zeminde (yeşil/sarı/turuncu) zeminin koyu, doygun bir tonu
    /// (referanstaki koyu-yeşil hissi); koyu zeminde (kırmızı dolgu, gri iz)
    /// beyaz. Eşik parlaklıkla belirleniyor, yani renk hangi tona kayarsa
    /// kaysın metin kendiliğinden okunur kalıyor.
    static func readableInk(on background: NSColor) -> NSColor {
        if luminance(background) >= 0.5 {
            let s = background.usingColorSpace(.sRGB) ?? background
            // Zeminin %22'si: aynı ton, çok koyu. Parlak dolguda yüksek kontrast.
            return NSColor(srgbRed: s.redComponent * 0.22, green: s.greenComponent * 0.22,
                           blue: s.blueComponent * 0.22, alpha: 1)
        }
        return .white
    }

    // MARK: - Çizim

    /// Tüm ikon TEK non-template görselde: demet + pil + geri sayım.
    ///
    /// `isTemplate = false` bilinçli: pilin rengi (kalan kotanın sağlığı) ve
    /// demetin rengi (servis durumu) bilgi taşıyor, menü çubuğu tonuna
    /// boyanmamalı. `ink` yalnızca geri sayım metni ve pilin izi için menü
    /// çubuğu tonunu (beyaz) taşıyor.
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

            drawPill(
                origin: CGPoint(x: l.pillX, y: (height - pillHeight) / 2),
                snapshot: snapshot, ink: ink, in: ctx
            )

            if !l.countdownText.isEmpty {
                let textColor = ink.withAlphaComponent(stale ? 0.5 : 1)
                drawSymbol("clock", at: CGPoint(x: l.clockX, y: mid), size: clockSize, color: textColor)
                draw(l.countdownText, font: textFont, at: CGPoint(x: l.countdownX, y: mid), color: textColor)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// macOS 26 tarzı pil: yatay kapsül, soldan dolan KALAN, içinde sayı.
    ///
    /// Katmanlar: iz (boş kısım, soluk) → dolgu (kalan, yakıt rengi, kapsüle
    /// kırpılı) → sayı. Sayı DOLGUYA ortalı ve kapsül içinde kırpılmayacak
    /// biçimde kenetli: dolgu genişse sayı dolgunun ortasında, dolgu daralınca
    /// sola yaslanıp iz üstüne taşıyor. Taşan kısım da okunur, çünkü sayı İKİ
    /// RENKLE çiziliyor: dolgu üstündeki bölümü zemine göre koyu, iz üstündeki
    /// bölümü beyaz. Kırpma tam dolgu sınırından geçtiği için her piksel kendi
    /// zeminine göre en okunur renkte.
    private static func drawPill(
        origin: CGPoint, snapshot: MenuBarSnapshot, ink: NSColor, in ctx: CGContext
    ) {
        let stale = snapshot.isStale
        let rect = CGRect(x: origin.x, y: origin.y, width: pillWidth, height: pillHeight)
        let radius = pillHeight / 2
        let pillPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // İz: boş kısım. Koyu menü çubuğunda beyaz@0,18 → koyu-gri; üstündeki
        // beyaz sayının okunması için bilinçli koyu (parlak-gri metni yerdi).
        ctx.saveGState()
        ctx.addPath(pillPath)
        ctx.setFillColor(ink.withAlphaComponent(stale ? 0.10 : 0.18).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        guard snapshot.hasData else { return }

        let remaining = min(max(1 - snapshot.usedPercent / 100, 0), 1)
        let fillColor = stale
            ? ink.withAlphaComponent(0.35)
            : gaugeColor(remaining: remaining)

        // Dolgu: kapsüle kırpılı dikdörtgen. Kalan çok azken bile bir iz kalsın
        // diye en az yarıçap kadar; sol uç kapsülü izliyor, sağ ucu düz.
        let fillWidth = remaining <= 0 ? 0 : max(radius, rect.width * remaining)
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        if fillWidth > 0 {
            ctx.saveGState()
            ctx.addPath(pillPath); ctx.clip()
            ctx.setFillColor(fillColor.cgColor)
            ctx.fill(fillRect)
            ctx.restoreGState()
        }

        // Sayı: KALAN yüzde, işaretsiz.
        let text = "\(snapshot.remainingPercent)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont]
        let size = text.size(withAttributes: attrs)

        // Yatay: dolguya ortalı, kapsül içine kenetli. Dolgu sayıyı içerecek
        // kadar genişse sayı dolgunun ortasında (dolgu büyüdükçe sağa kayar);
        // değilse sola yaslanıp iz üstüne taşar.
        let minX = rect.minX + pillTextInset
        let maxX = rect.maxX - pillTextInset - size.width
        var textX = fillRect.minX + (fillWidth - size.width) / 2
        textX = min(max(textX, minX), max(minX, maxX))
        let textY = rect.midY - size.height / 2
        let point = NSPoint(x: textX, y: textY)

        let inkOnFill = stale ? ink.withAlphaComponent(0.55) : readableInk(on: fillColor)
        let inkOnTrack = ink.withAlphaComponent(stale ? 0.45 : 1)
        let fillBoundary = fillRect.maxX

        // Dolgu üstündeki bölüm: zemine göre okunur renk.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: rect.minY,
                            width: max(0, fillBoundary - rect.minX), height: rect.height))
        text.draw(at: point, withAttributes: attrs.merging([.foregroundColor: inkOnFill]) { $1 })
        ctx.restoreGState()

        // İz üstündeki bölüm: beyaz.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: fillBoundary, y: rect.minY,
                            width: max(0, rect.maxX - fillBoundary), height: rect.height))
        text.draw(at: point, withAttributes: attrs.merging([.foregroundColor: inkOnTrack]) { $1 })
        ctx.restoreGState()
    }

    /// Menü çubuğu metni: verilen fontla, dikeyde ortalı.
    private static func draw(_ text: String, font: NSFont, at origin: CGPoint, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: origin.x, y: origin.y - size.height / 2), withAttributes: attrs)
    }

    /// Claude'un ışın demeti (kamalardan; ölçüler kurulu uygulamanın ikonundan).
    private static func drawClaudeMark(
        center: CGPoint, radius: CGFloat, color: NSColor, stale: Bool, in ctx: CGContext
    ) {
        let lengths: [CGFloat] = [1.0, 0.70, 0.94, 0.78, 1.0, 0.66, 0.90, 0.74, 0.98, 0.68, 0.86]
        let count = lengths.count
        let baseHalf = radius * 0.155
        let tipHalf = radius * 0.052

        ctx.saveGState()
        ctx.setFillColor(color.withAlphaComponent(stale ? 0.45 : 1).cgColor)

        for (index, factor) in lengths.enumerated() {
            let angle = Double.pi / 2 - Double(index) / Double(count) * 2 * Double.pi
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let perp = CGPoint(x: -dir.y, y: dir.x)
            let tip = radius * factor
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

        ctx.addArc(center: center, radius: radius * 0.20, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// SF Symbol çizimi (kum saati).
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
