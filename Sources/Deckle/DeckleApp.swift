import SwiftUI

@main
struct DeckleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item glyph: a filled paper sheet while the overlay is showing,
/// an outline while it's off or snoozed.
struct MenuBarLabel: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Image(nsImage: state.shouldShowOverlay ? Icons.menuOn : Icons.menuOff)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no app switcher entry. The bundled
        // app also sets LSUIElement, but this covers `swift run` during
        // development.
        NSApp.setActivationPolicy(.accessory)
        OverlayController.shared.start()
        HotKey.register()
        UpdateManager.shared.start()
    }
}
