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

    func apply(texture: TexturePreset, adjustments: TextureRenderer.GrainAdjustments) {
        textureView.apply(texture: texture, adjustments: adjustments)
    }
}

/// Shows the texture as a CALayer pattern background instead of drawing it.
/// A drawn view forces AppKit to allocate window-sized backing stores
/// (~30 MB per buffer on a Retina display); a pattern background color is
/// tiled by the CoreAnimation render server from the single 256×256 tile,
/// so the overlay costs kilobytes of process memory regardless of screen size.
final class TextureView: NSView {
    private var texture: TexturePreset?
    private var adjustments: TextureRenderer.GrainAdjustments = .none

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(texture: TexturePreset, adjustments: TextureRenderer.GrainAdjustments) {
        guard texture != self.texture || adjustments != self.adjustments else { return }
        self.texture = texture
        self.adjustments = adjustments
        let tile = TextureRenderer.compositeTile(for: texture, adjustments: adjustments)
        layer?.backgroundColor = NSColor(patternImage: tile).cgColor
    }
}
