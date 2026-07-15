import AppKit

/// Menu bar glyphs from the "1c — The Letter" icon concept: an italic serif
/// lowercase "d". Bold at full strength while the overlay is active; regular
/// at 40% while it's off — a glanceable state indicator. Drawn as template
/// images so they adapt to light/dark menu bars automatically.
enum Icons {
    static let menuOn = makeMenuIcon(active: true)
    static let menuOff = makeMenuIcon(active: false)

    private static func makeMenuIcon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            // Newsreader in the design; Georgia is the design's own fallback
            // and ships with macOS.
            let fontName = active ? "Georgia-BoldItalic" : "Georgia-Italic"
            let font = NSFont(name: fontName, size: 16)
                ?? NSFont.systemFont(ofSize: 16, weight: active ? .bold : .regular)
            let letter = NSAttributedString(string: "d", attributes: [
                .font: font,
                .foregroundColor: NSColor.black.withAlphaComponent(active ? 1.0 : 0.4),
            ])
            let size = letter.size()
            letter.draw(at: NSPoint(
                x: (rect.width - size.width) / 2,
                y: (rect.height - size.height) / 2
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}
