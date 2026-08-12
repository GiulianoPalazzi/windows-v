import AppKit
import Carbon.HIToolbox

final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    func register(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        let gHotKeyID = EventHotKeyID(signature: OSType(0x434C4853), id: 1)
        let mods: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_V)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            if let ctx = userData {
                let service = Unmanaged<HotkeyService>.fromOpaque(ctx).takeUnretainedValue()
                service.onTrigger?()
            }
            return noErr
        }
        let s1 = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let s2 = RegisterEventHotKey(keyCode, mods, gHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        _ = (s1, s2)
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let h = eventHandler { RemoveEventHandler(h) }
    }
}
