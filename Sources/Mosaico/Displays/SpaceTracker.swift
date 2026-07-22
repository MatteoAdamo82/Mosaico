import AppKit
import CAXShim

typealias NativeSpaceID = UInt64

/// Interroga gli Spaces nativi di macOS (Mission Control) via SPI CGS.
enum SpaceTracker {

    /// Space nativo attualmente visibile su ogni display.
    /// Chiave: "Display Identifier" (UUID string, o "Main" sul principale).
    static func activeSpacesByDisplay() -> [String: NativeSpaceID] {
        guard let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
            return [:]
        }
        var result: [String: NativeSpaceID] = [:]
        for display in raw {
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let id = (current["id64"] as? NativeSpaceID) ?? (current["ManagedSpaceID"] as? NativeSpaceID) else {
                continue
            }
            result[identifier] = id
        }
        return result
    }

    /// Space nativo corrente del display dato.
    static func currentSpace(for screen: NSScreen) -> NativeSpaceID? {
        let spaces = activeSpacesByDisplay()
        guard !spaces.isEmpty else { return nil }

        let displayID = DisplayManager.displayID(of: screen)
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let uuid = CFUUIDCreateString(nil, cfUUID) as String?,
           let id = spaces[uuid] {
            return id
        }
        // Il display principale a volte è identificato come "Main"
        if screen == NSScreen.screens.first, let id = spaces["Main"] {
            return id
        }
        // Un solo display: prendi l'unico valore
        if spaces.count == 1 { return spaces.values.first }
        return nil
    }

    /// Numero ordinale (1-based) dello space corrente del display, contando
    /// solo gli space utente (type 0, non fullscreen). Per l'indicatore menubar
    /// e per sapere quale Ctrl+N simulare.
    static func currentSpaceOrdinal(for screen: NSScreen) -> (current: Int, total: Int)? {
        guard let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        guard let currentID = currentSpace(for: screen) else { return nil }
        for display in raw {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let userSpaces = spaces.filter { ($0["type"] as? Int) == 0 }
            let ids = userSpaces.compactMap { $0["id64"] as? NativeSpaceID }
            if let index = ids.firstIndex(of: currentID) {
                return (index + 1, ids.count)
            }
        }
        return nil
    }

    /// Space nativo su cui vive una finestra.
    static func space(of windowID: WindowID) -> NativeSpaceID? {
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let raw = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, windows)?.takeRetainedValue() as? [NSNumber],
              let first = raw.first else {
            return nil
        }
        return first.uint64Value
    }
}
