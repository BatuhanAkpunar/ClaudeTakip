import AppKit

// ClaudeTakip uygulama ikonu.
// Kimlik: uygulamanın kartlarındaki kullanım kadranı. Indigo→mor squircle
// gövde, üstünde teal bir doluluk yayı ve ucunda projeksiyon noktası.
// Native Big Sur yerleşimi: 1024 tuval içinde ~824 gövde, yumuşak gölge.
//
// Kullanım: swift tools/makeicon.swift icon_1024.png
// Diğer boyutlar:
//   for s in 16 32 64 128 256 512; do sips -z $s $s icon_1024.png --out icon_$s.png; done

guard CommandLine.arguments.count > 1 else { print("kullanım: swift tools/makeicon.swift <çıktı.png>"); exit(1) }

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

// Gövde squircle
let inset = 100.0
let body = CGRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let radius = body.width * 0.2237
let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Yumuşak gölge
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40,
              color: color(20, 10, 60, 0.45))
ctx.addPath(path); ctx.setFillColor(color(0,0,0,1)); ctx.fillPath()
ctx.restoreGState()

// Gövde gradyanı (indigo → mor), köşegen
ctx.saveGState()
ctx.addPath(path); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(60, 42, 220), color(120, 84, 255)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: body.minX, y: body.maxY),
    end: CGPoint(x: body.maxX, y: body.minY), options: [])
// Üstte hafif ışık
let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(255,255,255,0.16), color(255,255,255,0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: size/2, y: body.maxY - 40),
    startRadius: 0, endCenter: CGPoint(x: size/2, y: body.maxY - 40),
    endRadius: body.width * 0.7, options: [])
ctx.restoreGState()

// Kadran
let center = CGPoint(x: size/2, y: size/2)
let ringR = body.width * 0.30
let lineW = body.width * 0.115
// Track
ctx.setLineWidth(lineW)
ctx.setStrokeColor(color(255,255,255,0.20))
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: ringR, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.strokePath()
// Doluluk yayı: tepeden (%0) saat yönünde %66
let start = Double.pi/2            // tepe (CG'de yukarı = +y, açı 90°)
let frac = 0.66
let end = start - frac * 2 * Double.pi  // saat yönü (azalan açı)
ctx.setLineWidth(lineW)
ctx.setStrokeColor(color(48, 214, 200, 1))   // teal
ctx.addArc(center: center, radius: ringR, startAngle: start, endAngle: end, clockwise: true)
ctx.strokePath()
// Yay ucunda nokta
let dot = CGPoint(x: center.x + cos(end)*ringR, y: center.y + sin(end)*ringR)
ctx.setFillColor(color(255,255,255,1))
ctx.addArc(center: dot, radius: lineW*0.42, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.fillPath()

img.unlockFocus()
let tiff = img.tiffRepresentation!
let bmp = NSBitmapImageRep(data: tiff)!
let png = bmp.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("yazıldı")
