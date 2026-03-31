import AppKit

@MainActor
final class MenuBarIconRenderer {
    private let logoImage: NSImage?
    private var flashTimer: Timer?
    private var isFlashVisible: Bool = true

    init() {
        logoImage = NSImage(named: "ClaudeLogo")
    }

    func startFlashAnimation(updateHandler: @escaping () -> Void) {
        guard flashTimer == nil else { return }
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isFlashVisible.toggle()
                updateHandler()
            }
        }
    }

    func stopFlashAnimation() {
        flashTimer?.invalidate()
        flashTimer = nil
        isFlashVisible = true
    }

    func render(remaining: Double, resetTimeText: String) -> NSImage {
        let logoSize: CGFloat = 16
        let barWidth: CGFloat = 48
        let barHeight: CGFloat = 14
        let spacing: CGFloat = 4
        let timeWidth: CGFloat = 36
        let totalWidth = logoSize + spacing + barWidth + spacing + timeWidth
        let totalHeight: CGFloat = 22

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()

        let yCenter = totalHeight / 2

        // 1. Claude logo
        if let logo = logoImage {
            let logoRect = NSRect(x: 0, y: yCenter - logoSize / 2, width: logoSize, height: logoSize)
            logo.draw(in: logoRect)
        }

        // 2. Progress bar
        let barX = logoSize + spacing
        let barY = yCenter - barHeight / 2
        let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)

        // Track
        let trackPath = NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.816, alpha: 1)).setFill()
        trackPath.fill()

        // Fill (flash animation when <10%)
        let fillWidth = barWidth * CGFloat(max(0, min(1, remaining)))
        if fillWidth > 0 {
            let showFill = remaining >= 0.10 || isFlashVisible
            if showFill {
                let fillRect = NSRect(x: barX, y: barY, width: fillWidth, height: barHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
                statusColor(for: remaining).setFill()
                fillPath.fill()
            }
        }

        // Percentage text inside bar
        let percentText = "\(Int(remaining * 100))%"
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let percentSize = (percentText as NSString).size(withAttributes: percentAttrs)
        let percentX = barX + (barWidth - percentSize.width) / 2
        let percentY = yCenter - percentSize.height / 2
        (percentText as NSString).draw(at: NSPoint(x: percentX, y: percentY), withAttributes: percentAttrs)

        // 3. Reset time
        let timeX = barX + barWidth + spacing
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isDark ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.6, alpha: 1)
        ]
        let timeSize = (resetTimeText as NSString).size(withAttributes: timeAttrs)
        let timeY = yCenter - timeSize.height / 2
        (resetTimeText as NSString).draw(at: NSPoint(x: timeX, y: timeY), withAttributes: timeAttrs)

        image.unlockFocus()
        return image
    }

    private func statusColor(for remaining: Double) -> NSColor {
        switch remaining {
        case 0.50...: return NSColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 1)    // neon cyan #00F0FF
        case 0.25..<0.50: return NSColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1) // neon amber #FFB800
        default: return NSColor(red: 1.0, green: 0.18, blue: 0.47, alpha: 1)          // neon magenta #FF2D78
        }
    }

    static func formatResetTime(from date: Date?) -> String {
        guard let date, date > Date() else { return "--:--" }
        let remaining = date.timeIntervalSince(Date())
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
