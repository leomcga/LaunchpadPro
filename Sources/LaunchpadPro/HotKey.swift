import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via the Carbon Events API.
/// Carbon hotkeys work without Accessibility permission, which keeps the
/// personal build friction-free.
final class HotKeyManager {

    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onFire: (() -> Void)?

    private let signature: OSType = {
        // 'LOPr'
        let s: [UInt8] = [0x4C, 0x4F, 0x50, 0x72]
        return (OSType(s[0]) << 24) | (OSType(s[1]) << 16) | (OSType(s[2]) << 8) | OSType(s[3])
    }()

    /// keyCode + modifier (Carbon) — default is ⌥Space (Option-Space).
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        onFire = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { manager.onFire?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let handler = eventHandler { RemoveEventHandler(handler); eventHandler = nil }
    }
}

enum HotKeyDefaults {
    static let optionSpace = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let f4 = (keyCode: UInt32(kVK_F4), modifiers: UInt32(0))
}
