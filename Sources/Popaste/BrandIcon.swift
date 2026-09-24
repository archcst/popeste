import AppKit

/// The ribbon P, matching assets/logo.svg. Coordinates use the SVG's 100-point grid.
enum BrandIcon {
    static func drawMark(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.move(to: NSPoint(x: 27, y: 84))
        path.line(to: NSPoint(x: 27, y: 19))
        path.line(to: NSPoint(x: 55, y: 19))
        path.curve(to: NSPoint(x: 82, y: 44), controlPoint1: NSPoint(x: 72, y: 19), controlPoint2: NSPoint(x: 82, y: 29))
        path.curve(to: NSPoint(x: 55, y: 69), controlPoint1: NSPoint(x: 82, y: 59), controlPoint2: NSPoint(x: 72, y: 69))
        path.line(to: NSPoint(x: 44, y: 69))
        path.close()
        path.move(to: NSPoint(x: 44, y: 35))
        path.line(to: NSPoint(x: 44, y: 53))
        path.line(to: NSPoint(x: 55, y: 53))
        path.curve(to: NSPoint(x: 66, y: 44), controlPoint1: NSPoint(x: 62, y: 53), controlPoint2: NSPoint(x: 66, y: 50))
        path.curve(to: NSPoint(x: 55, y: 35), controlPoint1: NSPoint(x: 66, y: 38), controlPoint2: NSPoint(x: 62, y: 35))
        path.close()
        path.transform(using: AffineTransform(m11: rect.width / 100, m12: 0, m21: 0, m22: -rect.height / 100, tX: rect.minX, tY: rect.maxY))
        color.setFill()
        path.fill()
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            // Fit the visible 55 × 65 outline into a centered 13 × 15 point mark.
            drawMark(in: NSRect(x: -3.58, y: -2.19, width: 23.08, height: 23.08), color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Popeste"
        return image
    }

    static func drawAppIcon(size: CGFloat) {
        let tile = NSRect(x: size * 0.10, y: size * 0.10, width: size * 0.80, height: size * 0.80)
        let outline = NSBezierPath(roundedRect: tile, xRadius: size * 0.20, yRadius: size * 0.20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = size * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.set()
        NSColor(red: 1, green: 196/255, blue: 0, alpha: 1).setFill()
        outline.fill()
        NSGraphicsContext.restoreGraphicsState()
        let markSize = tile.width * 0.77
        drawMark(in: NSRect(x: tile.midX - markSize / 2, y: tile.midY - markSize / 2, width: markSize, height: markSize), color: .white)
    }
}
