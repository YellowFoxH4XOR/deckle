import AppKit
import Combine

/// Owns one OverlayWindow per display and keeps them in sync with AppState
/// and with display configuration changes (plug/unplug, resolution change).
final class OverlayController {
    static let shared = OverlayController()

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func start() {
        // objectWillChange fires before the mutation lands, so hop to the
        // next runloop tick to read the updated values.
        AppState.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }

        refresh()
    }

    func refresh() {
        let state = AppState.shared
        var seen: Set<CGDirectDisplayID> = []

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            seen.insert(displayID)

            let excluded = state.excludedDisplays.contains(String(displayID))
            let visible = state.shouldShowOverlay && !excluded

            // .none removes the overlay from screenshots/recordings while it
            // stays visible on the physical display. Changing sharingType on
            // an onscreen window doesn't reliably reach the window server, so
            // it is only ever set before a window first orders front — when
            // the setting changes, the window is rebuilt.
            let sharing: NSWindow.SharingType = state.hideFromCapture ? .none : .readOnly
            if let existing = windows[displayID], existing.sharingType != sharing {
                existing.orderOut(nil)
                windows.removeValue(forKey: displayID)
            }

            let window = windows[displayID] ?? {
                let created = OverlayWindow(screen: screen)
                created.sharingType = sharing
                windows[displayID] = created
                return created
            }()

            window.setFrame(screen.frame, display: true)
            window.apply(texture: state.texture, adjustments: state.grainAdjustments)

            if visible {
                if window.isVisible {
                    // Already showing (e.g. slider drag): track directly,
                    // animating every tick would lag behind the slider.
                    window.alphaValue = CGFloat(state.intensity)
                } else {
                    window.alphaValue = 0
                    window.orderFrontRegardless()
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.4
                        window.animator().alphaValue = CGFloat(state.intensity)
                    }
                }
            } else if window.isVisible {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.4
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    // Only detach if nothing re-showed it mid-fade (a re-show
                    // would have restored a non-zero alpha).
                    if window.alphaValue == 0 {
                        window.orderOut(nil)
                    }
                })
            }
        }

        // Drop windows for displays that went away.
        for (displayID, window) in windows where !seen.contains(displayID) {
            window.orderOut(nil)
            windows.removeValue(forKey: displayID)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
