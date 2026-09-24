import SwiftUI
import AppKit
import LimitCore

#if DEBUG

/// Menü çubuğu ikonunu birkaç durumda, açık ve koyu çubukta önizler.
@MainActor
enum BatteryPreview {
    static func render(to path: String) {
        // usedPercent: kalan = 100 - kullanılan. Yeşilden kırmızıya tüm bandı
        // gezmek için birçok değer + servis kesintisi + bayat + veri yok.
        let cases: [(String, MenuBarSnapshot)] = [
            ("kalan 100", .sample(used: 0)),
            ("kalan 85", .sample(used: 15)),
            ("kalan 67", .sample(used: 33)),
            ("kalan 50", .sample(used: 50)),
            ("kalan 33", .sample(used: 67)),
            ("kalan 20", .sample(used: 80)),
            ("kalan 8", .sample(used: 92)),
            ("kalan 0", .sample(used: 100)),
            ("kesinti", .sample(used: 40, serviceOK: false)),
            ("bayat", .sample(used: 40, stale: true)),
            ("veri yok", .noData),
        ]
        // Menü çubuğu 22 pt; iki ölçekte çiziyoruz: 1× (gerçek boy) ve 3×
        // (okunurluk denetimi). Zemin koyu vibrant menü çubuğunu taklit ediyor.
        let scales: [(String, CGFloat)] = [("1x", 1), ("3x", 3)]
        let rowH: CGFloat = 40
        let colW: CGFloat = 180
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
                let icon = MenuBarIconRenderer.colorImage(for: item.1, ink: .white)
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
        // olmadığı için `render(view:)` düz bir arka plan (`Palette.previewBackdrop`)
        // ekliyor.
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
