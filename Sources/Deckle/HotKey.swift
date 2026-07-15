import AppKit
import Carbon.HIToolbox

/// Global ⌥⌘P shortcut that toggles the overlay from anywhere.
/// Uses Carbon's RegisterEventHotKey, which needs no accessibility
/// permissions (unlike CGEventTap-based approaches).
enum HotKey {
    private static var hotKeyRef: EventHotKeyRef?

    static func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C callback: no captures allowed, so it reaches for the singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                let state = AppState.shared
                if state.shouldShowOverlay {
                    state.isEnabled = false
                } else {
                    state.cancelSnooze()
                    state.isEnabled = true
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: 0x4443_4B4C /* 'DCKL' */, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
