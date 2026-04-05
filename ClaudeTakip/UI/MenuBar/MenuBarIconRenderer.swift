import AppKit

@MainActor
final class MenuBarIconRenderer {
    private let logoImage: NSImage?

    // Official Claude asterisk SVG path (viewBox 0 0 24 24), color #D97757
    private static let claudeSVG = """
    <svg width="64" height="64" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">\
    <path d="M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339\
    -.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 \
    1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336\
    -.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 \
    2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032\
    -.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 \
    1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23\
    -2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 \
    1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129\
    -.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 \
    1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042\
    .03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64\
    -.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578\
    -.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521\
    .122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08\
    -.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286\
    -1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717\
    -.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 \
    18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z" fill="#D97757" \
    fill-rule="nonzero"/></svg>
    """

    init() {
        if let data = Self.claudeSVG.data(using: .utf8),
           let logo = NSImage(data: data) {
            logo.isTemplate = false
            logo.size = NSSize(width: 16, height: 16)
            self.logoImage = logo
        } else {
            self.logoImage = nil
        }
    }

    /// Menu bar: [Claude logo] [pil bar + %XX] [H:MM]
    func render(remaining: Double, resetTimeText: String, hasLoaded: Bool) -> NSImage {
        let logoSize: CGFloat = 16
        let gap: CGFloat = 4
        let barWidth: CGFloat = 36
        let barHeight: CGFloat = 18
        let barRadius: CGFloat = 4
        let timeGap: CGFloat = 4
        let totalHeight: CGFloat = 22

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Percentage text
        let percentText = hasLoaded ? "\(Int(remaining * 100))%" : "--%"
        let percentColor = isDark ? NSColor.white : NSColor.black
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: percentColor
        ]
        let percentSize = (percentText as NSString).size(withAttributes: percentAttrs)

        // Time text
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let timeSize = (resetTimeText as NSString).size(withAttributes: timeAttrs)

        let totalWidth = logoSize + gap + barWidth + timeGap + timeSize.width + 1

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()

        let yCenter = totalHeight / 2

        // 1. Claude logo
        if let logo = logoImage {
            let logoRect = NSRect(x: 0, y: yCenter - logoSize / 2, width: logoSize, height: logoSize)
            logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // 2. Battery bar
        let barX = logoSize + gap
        let barY = yCenter - barHeight / 2
        let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)

        // Track
        let trackPath = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)
        (isDark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.85, alpha: 1)).setFill()
        trackPath.fill()

        // Border
        let borderPath = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)
        (isDark ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.62, alpha: 1)).setStroke()
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        // Fill — always visible
        let clampedRemaining = max(0, min(1, remaining))
        let fillInset: CGFloat = 1.5
        let fillWidth = (barWidth - fillInset * 2) * CGFloat(clampedRemaining)
        if fillWidth > 0 && hasLoaded {
            let fillRect = NSRect(x: barX + fillInset, y: barY + fillInset, width: fillWidth, height: barHeight - fillInset * 2)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barRadius - 1, yRadius: barRadius - 1)
            statusColor(for: remaining).setFill()
            fillPath.fill()
        }

        // Percentage text (shadow + white)
        let percentX = barX + (barWidth - percentSize.width) / 2
        let percentY = yCenter - percentSize.height / 2

        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.5) : NSColor.white.withAlphaComponent(0.6)
        let shadowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: shadowColor
        ]
        (percentText as NSString).draw(at: NSPoint(x: percentX + 0.5, y: percentY - 0.5), withAttributes: shadowAttrs)
        (percentText as NSString).draw(at: NSPoint(x: percentX, y: percentY), withAttributes: percentAttrs)

        // 3. Reset time
        let timeX = barX + barWidth + timeGap
        let timeY = yCenter - timeSize.height / 2
        (resetTimeText as NSString).draw(at: NSPoint(x: timeX, y: timeY), withAttributes: timeAttrs)

        image.unlockFocus()
        return image
    }

    private func statusColor(for remaining: Double) -> NSColor {
        switch remaining {
        case 0.50...: return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case 0.25..<0.50: return NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
        default: return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
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
