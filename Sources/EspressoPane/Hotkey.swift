import Carbon.HIToolbox
import AppKit

/// Global panic hotkey — ⌃⇧⎋ (Ctrl+Shift+Escape), matching the original
/// Espresso. Carbon hotkeys are system-wide and need no Accessibility grant.
final class PanicHotkey {
    static let shared = PanicHotkey()
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { PanicHotkey.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x56595650), id: 1) // 'ESPRESSOP'
        RegisterEventHotKey(UInt32(kVK_Escape),
                            UInt32(controlKey | shiftKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
