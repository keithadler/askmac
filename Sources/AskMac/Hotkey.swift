//  Ask for Mac — MIT licensed. See LICENSE.
//
//  ⌥Space brings the window forward from anywhere, the way a question comes to mind. Off in Settings.

import AppKit
import Carbon

enum Hotkey {
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    static var onPress: () -> Void = {}

    static func register() {
        unregister()
        guard Prefs.hotkey else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in Hotkey.onPress(); return noErr }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x41534B4D), id: 1)   // "ASKM"
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
    static func unregister() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
