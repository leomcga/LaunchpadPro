import AppKit

enum AppBranding {
    static func icon(size: NSSize? = nil) -> NSImage? {
        let image: NSImage?
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") {
            image = NSImage(contentsOf: url)
        } else {
            image = NSImage(named: "AppIcon")
        }

        guard let image else { return nil }
        if let size {
            image.size = size
        }
        image.isTemplate = false
        return image
    }

    static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 19, height: 19)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outer = NSBezierPath(
            roundedRect: NSRect(x: 2.1, y: 2.0, width: 14.8, height: 14.8),
            xRadius: 4.6,
            yRadius: 4.6
        )
        outer.lineWidth = 1.55
        outer.stroke()

        let body = NSBezierPath(roundedRect: NSRect(x: 8.1, y: 6.1, width: 3.4, height: 7.8), xRadius: 1.7, yRadius: 1.7)
        body.fill()

        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: 9.8, y: 15.3))
        nose.curve(to: NSPoint(x: 12.1, y: 12.5), controlPoint1: NSPoint(x: 11.1, y: 14.6), controlPoint2: NSPoint(x: 11.8, y: 13.5))
        nose.line(to: NSPoint(x: 7.5, y: 12.5))
        nose.curve(to: NSPoint(x: 9.8, y: 15.3), controlPoint1: NSPoint(x: 7.8, y: 13.5), controlPoint2: NSPoint(x: 8.5, y: 14.6))
        nose.close()
        nose.fill()

        let leftFin = NSBezierPath()
        leftFin.move(to: NSPoint(x: 8.15, y: 7.1))
        leftFin.line(to: NSPoint(x: 5.85, y: 4.85))
        leftFin.curve(to: NSPoint(x: 7.4, y: 8.65), controlPoint1: NSPoint(x: 5.95, y: 6.35), controlPoint2: NSPoint(x: 6.55, y: 7.65))
        leftFin.close()
        leftFin.fill()

        let rightFin = NSBezierPath()
        rightFin.move(to: NSPoint(x: 11.45, y: 7.1))
        rightFin.line(to: NSPoint(x: 13.75, y: 4.85))
        rightFin.curve(to: NSPoint(x: 12.2, y: 8.65), controlPoint1: NSPoint(x: 13.65, y: 6.35), controlPoint2: NSPoint(x: 13.05, y: 7.65))
        rightFin.close()
        rightFin.fill()

        let flame = NSBezierPath()
        flame.move(to: NSPoint(x: 9.8, y: 2.9))
        flame.curve(to: NSPoint(x: 11.0, y: 5.8), controlPoint1: NSPoint(x: 10.6, y: 4.0), controlPoint2: NSPoint(x: 11.0, y: 4.8))
        flame.line(to: NSPoint(x: 8.6, y: 5.8))
        flame.curve(to: NSPoint(x: 9.8, y: 2.9), controlPoint1: NSPoint(x: 8.6, y: 4.8), controlPoint2: NSPoint(x: 9.0, y: 4.0))
        flame.close()
        flame.fill()

        let window = NSBezierPath(ovalIn: NSRect(x: 8.75, y: 10.1, width: 2.1, height: 2.1))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        window.fill()
        NSGraphicsContext.restoreGraphicsState()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "LaunchpadPro Codex"
        return image
    }
}
