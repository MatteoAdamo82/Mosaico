import Carbon.HIToolbox
import AppKit

/// Hotkey globali via Carbon RegisterEventHotKey: nessun permesso extra,
/// consuma il keystroke, rispetta Secure Input.
final class HotkeyManager {
    var onCommand: ((Command) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var commandsByID: [UInt32: Command] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    func register(_ bindings: [KeyBinding]) {
        unregisterAll()
        installHandlerIfNeeded()

        for binding in bindings {
            let id = nextID
            nextID += 1

            var hotKeyID = EventHotKeyID(signature: OSType(0x4D4F5341 /* 'MOSA' */), id: id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode,
                                             binding.carbonModifiers,
                                             hotKeyID,
                                             GetEventDispatcherTarget(),
                                             0,
                                             &ref)
            if status == noErr, ref != nil {
                hotKeyRefs.append(ref)
                commandsByID[id] = binding.command
            } else {
                // Collisione con un'altra app o con una scorciatoia di sistema
                MosaicoLog.log("hotkey non registrata (\(status)): \(binding.displayString) → \(binding.command.title)")
            }
            _ = hotKeyID
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        commandsByID.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)

            if let command = manager.commandsByID[hotKeyID.id] {
                DispatchQueue.main.async {
                    manager.onCommand?(command)
                }
            }
            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, userData, &eventHandler)
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
