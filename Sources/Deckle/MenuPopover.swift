import AppKit
import SwiftUI

/// Fits the menu to its content, keeping the native MenuBarExtra window in sync.
/// MenuBarExtra does not reliably shrink its window when SwiftUI content size decreases,
/// which can leave a blank frosted-glass region at the bottom.
/// MenuPopover actively synchronizes the native window frame with the content's measured height
/// and guarantees an opaque background across the entire popover.
@MainActor
struct MenuPopover<Content: View>: View {
    let preferredWidth: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0
    @State private var availableMaxHeight: CGFloat = .infinity

    var body: some View {
        let isConstrained = measuredHeight > availableMaxHeight && availableMaxHeight > 0
        let effectiveHeight = measuredHeight > 0 ? min(measuredHeight, availableMaxHeight) : nil

        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor).opacity(0.96)
                .ignoresSafeArea()

            if isConstrained {
                ScrollView(.vertical) {
                    content()
                        .frame(width: preferredWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(sizingView)
                }
                .frame(width: preferredWidth, height: effectiveHeight, alignment: .top)
            } else {
                content()
                    .frame(width: preferredWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(sizingView)
                    .frame(width: preferredWidth, height: effectiveHeight, alignment: .top)
            }
        }
        .frame(width: preferredWidth, height: effectiveHeight, alignment: .top)
    }

    private var sizingView: some View {
        MenuSizingRepresentable { height, maxH in
            if abs(measuredHeight - height) >= 0.5 {
                measuredHeight = height
            }
            if abs(availableMaxHeight - maxH) >= 0.5 {
                availableMaxHeight = maxH
            }
        }
    }
}

/// Geometry uses AppKit's bottom-left screen coordinates, including displays
/// left of or below the primary screen. Shrinking preserves the menu's top.
enum MenuPopoverGeometry {
    static func frame(size: CGSize, anchoredTo current: CGRect, visibleFrame: CGRect) -> CGRect {
        let top = min(current.maxY, visibleFrame.maxY)
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, max(0, top - visibleFrame.minY))
        return CGRect(
            x: min(max(current.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: top - height,
            width: width,
            height: height
        )
    }
}

@MainActor
private struct MenuSizingRepresentable: NSViewRepresentable {
    let onSizeChanged: @MainActor (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> MenuSizingView {
        let view = MenuSizingView()
        view.onSizeChanged = onSizeChanged
        return view
    }

    func updateNSView(_ nsView: MenuSizingView, context: Context) {
        nsView.onSizeChanged = onSizeChanged
        nsView.scheduleSizing()
    }

    static func dismantleNSView(_ nsView: MenuSizingView, coordinator: ()) {
        nsView.stopObserving()
        nsView.onSizeChanged = nil
    }
}

@MainActor
final class MenuSizingView: NSView {
    var onSizeChanged: (@MainActor (CGFloat, CGFloat) -> Void)?
    private var sizingScheduled = false
    private var lastMeasuredHeight: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [
            NSWindow.didMoveNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeOcclusionStateNotification
        ] {
            center.addObserver(self, selector: #selector(windowGeometryChanged), name: name, object: window)
        }
        center.addObserver(
            self,
            selector: #selector(windowGeometryChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        scheduleSizing()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.height > 50, newSize.width > 0 else { return }
        if abs(newSize.height - lastMeasuredHeight) >= 0.5 {
            lastMeasuredHeight = newSize.height
            scheduleSizing()
        }
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowGeometryChanged(_ notification: Notification) {
        scheduleSizing()
    }

    func scheduleSizing() {
        guard !sizingScheduled else { return }
        sizingScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizingScheduled = false
            self.synchronizeWindow()
        }
    }

    private func synchronizeWindow() {
        guard let window, window.isVisible, let screen = window.screen,
              lastMeasuredHeight > 50 else { return }

        let visible = screen.visibleFrame
        let top = min(window.frame.maxY, visible.maxY)
        let maxHeight = max(100, top - visible.minY)
        let targetHeight = min(lastMeasuredHeight, maxHeight)

        onSizeChanged?(lastMeasuredHeight, maxHeight)

        let targetWidth = bounds.width > 0 ? bounds.width : window.frame.width
        let target = MenuPopoverGeometry.frame(
            size: CGSize(width: targetWidth, height: targetHeight),
            anchoredTo: window.frame,
            visibleFrame: visible
        )

        let tolerance = 1 / window.backingScaleFactor
        guard abs(target.width - window.frame.width) >= tolerance
            || abs(target.height - window.frame.height) >= tolerance
            || abs(target.minX - window.frame.minX) >= tolerance
            || abs(target.minY - window.frame.minY) >= tolerance else { return }

        window.setFrame(target, display: true, animate: false)
    }
}
