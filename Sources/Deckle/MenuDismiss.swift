import AppKit

/// Dismisses an open MenuBarExtra content window before presenting a
/// standalone window. It deliberately ignores generic panels and status-bar
/// windows so colour pickers and the app's menu-bar entry stay untouched.
enum MenuDismiss {
    @MainActor
    static func dismiss() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("Popover") {
                window.orderOut(nil)
            }
        }
    }
}
