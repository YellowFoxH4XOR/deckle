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

    func apply(
        texture: TexturePreset,
        adjustments: TextureRenderer.GrainAdjustments,
        deskLampEnabled: Bool = AppState.shared.enableDeskLamp,
        lampWarmth: Double = AppState.shared.deskLampWarmth,
        lampBrightness: Double = AppState.shared.deskLampBrightness,
        lampSpread: Double = AppState.shared.deskLampSpread,
        lampPosition: AppState.LampPosition = AppState.shared.deskLampPosition
    ) {
        textureView.apply(
            texture: texture,
            adjustments: adjustments,
            deskLampEnabled: deskLampEnabled,
            lampWarmth: lampWarmth,
            lampBrightness: lampBrightness,
            spread: lampSpread,
            lampPosition: lampPosition
        )
    }
}

/// Shows the texture as a CALayer pattern background instead of drawing it.
/// A drawn view forces AppKit to allocate window-sized backing stores
/// (~30 MB per buffer on a Retina display); a pattern background color is
/// tiled by the CoreAnimation render server from the single 256×256 tile,
/// so the overlay costs kilobytes of process memory regardless of screen size.
final class TextureView: NSView {
    override var isFlipped: Bool { true }

    private var texture: TexturePreset?
    private var adjustments: TextureRenderer.GrainAdjustments = .none
    private var lampLayer: CAGradientLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        lampLayer?.frame = bounds
    }

    func apply(
        texture: TexturePreset,
        adjustments: TextureRenderer.GrainAdjustments,
        deskLampEnabled: Bool = AppState.shared.enableDeskLamp,
        lampWarmth: Double = AppState.shared.deskLampWarmth,
        lampBrightness: Double = AppState.shared.deskLampBrightness,
        lampSpread: Double = AppState.shared.deskLampSpread,
        lampPosition: AppState.LampPosition = AppState.shared.deskLampPosition
    ) {
        if texture != self.texture || adjustments != self.adjustments {
            self.texture = texture
            self.adjustments = adjustments
            let tile = TextureRenderer.compositeTile(for: texture, adjustments: adjustments)
            layer?.backgroundColor = NSColor(patternImage: tile).cgColor
        }

        updateDeskLampLayer(
            enabled: deskLampEnabled,
            warmth: lampWarmth,
            brightness: lampBrightness,
            spread: lampSpread,
            position: lampPosition
        )
    }

    private func updateDeskLampLayer(
        enabled: Bool,
        warmth: Double,
        brightness: Double,
        spread: Double,
        position: AppState.LampPosition
    ) {
        guard enabled else {
            lampLayer?.removeFromSuperlayer()
            lampLayer = nil
            return
        }

        let lamp = lampLayer ?? {
            let l = CAGradientLayer()
            l.type = .radial
            l.frame = bounds
            layer?.addSublayer(l)
            lampLayer = l
            return l
        }()

        lamp.frame = bounds
        let center = position.point
        lamp.startPoint = center
        lamp.endPoint = CGPoint(
            x: center.x + CGFloat(spread),
            y: center.y + CGFloat(spread)
        )

        // Interpolate warm incandescent light tint based on warmth parameter
        // warmth = 0 -> cool neutral off-white (255, 250, 240)
        // warmth = 1 -> deep warm amber (255, 180, 100)
        let r: CGFloat = 1.0
        let g: CGFloat = 0.98 - CGFloat(warmth) * 0.28
        let b: CGFloat = 0.92 - CGFloat(warmth) * 0.52
        let alpha = CGFloat(brightness)

        let centerColor = NSColor(srgbRed: r, green: g, blue: b, alpha: alpha).cgColor
        let midColor = NSColor(srgbRed: r, green: g, blue: b, alpha: alpha * 0.4).cgColor
        let edgeColor = NSColor.clear.cgColor

        lamp.colors = [centerColor, midColor, edgeColor]
        lamp.locations = [0.0, 0.45, 1.0]
    }
}
