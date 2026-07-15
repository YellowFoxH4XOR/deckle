import AppKit

/// A borderless, transparent, click-through window that sits above everything
/// (including the menu bar) and simply draws the paper texture.
final class OverlayWindow: NSWindow {
    private let textureView = TextureView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Above the menu bar and normal fullscreen content.
        level = .screenSaver
        // Follow the user to every Space, stay put during Mission Control,
        // and never show up in the window cycle (Cmd-`).
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        contentView = textureView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(texture: TexturePreset) {
        textureView.apply(texture: texture)
    }
}

/// Draws the tint wash plus the tiled grain pattern.
final class TextureView: NSView {
    private var texture: TexturePreset?
    private var tile: NSImage?

    func apply(texture: TexturePreset) {
        guard texture != self.texture else { return }
        self.texture = texture
        self.tile = TextureRenderer.tile(for: texture)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let texture, let tile else { return }
        texture.tint.withAlphaComponent(texture.tintAlpha).setFill()
        bounds.fill(using: .sourceOver)
        NSColor(patternImage: tile).setFill()
        bounds.fill(using: .sourceOver)
    }
}
