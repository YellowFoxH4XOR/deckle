import AppKit

/// Menu bar glyphs, drawn in code as template images so they adapt to
/// light/dark menu bars automatically. The sheet is filled while the overlay
/// is active and outlined while it's off — a glanceable state indicator.
enum Icons {
    static let menuOn = makeMenuIcon(filled: true)
    static let menuOff = makeMenuIcon(filled: false)

    private static func makeMenuIcon(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let sheet = NSRect(x: 3.5, y: 2.5, width: 11, height: 13)
            let fold: CGFloat = 4

            let path = NSBezierPath()
            path.move(to: NSPoint(x: sheet.minX, y: sheet.minY))
            path.line(to: NSPoint(x: sheet.maxX, y: sheet.minY))
            path.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
            path.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
            path.line(to: NSPoint(x: sheet.minX, y: sheet.maxY))
            path.close()

            let flap = NSBezierPath()
            flap.move(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
            flap.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
            flap.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY - fold))
            flap.close()

            if filled {
                NSColor.black.setFill()
                path.fill()
                // Knock the flap out so the fold reads even when filled
                NSColor.black.withAlphaComponent(0.35).setFill()
                flap.fill()
            } else {
                NSColor.black.setStroke()
                path.lineWidth = 1.4
                path.stroke()
                flap.lineWidth = 1
                NSColor.black.withAlphaComponent(0.7).setStroke()
                flap.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
