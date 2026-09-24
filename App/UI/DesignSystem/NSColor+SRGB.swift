import AppKit

extension NSColor {
    /// 0-255 bileşenlerden opak sRGB renk.
    static func srgb255(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
