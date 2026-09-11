import AppKit
import CAXShim

typealias NativeSpaceID = UInt64

/// Queries macOS native Spaces (Mission Control) via CGS SPI.
enum SpaceTracker {

    /// Native space currently visible on each display.
    /// Key: "Display Identifier" (UUID string, or "Main" on the primary).
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

    /// Current native space of the given display.
    static func currentSpace(for screen: NSScreen) -> NativeSpaceID? {
        currentSpace(for: screen, in: activeSpacesByDisplay())
    }

    /// Same, against an already fetched display→space map: one CGS call
    /// serves every display of a pass.
    static func currentSpace(for screen: NSScreen, in spaces: [String: NativeSpaceID]) -> NativeSpaceID? {
        guard !spaces.isEmpty else { return nil }

        let displayID = DisplayManager.displayID(of: screen)
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let uuid = CFUUIDCreateString(nil, cfUUID) as String?,
           let id = spaces[uuid] {
            return id
        }
        // The primary display is sometimes identified as "Main"
        if screen == NSScreen.screens.first, let id = spaces["Main"] {
            return id
        }
        // Only one display: take the single value
        if spaces.count == 1 { return spaces.values.first }
        return nil
    }

    /// Ordinal number (1-based) of the display's current space, counting
    /// only user spaces (type 0, not fullscreen). For the menubar indicator
    /// and to know which Ctrl+N to simulate.
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

    /// Native space a window lives on.
    static func space(of windowID: WindowID) -> NativeSpaceID? {
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let raw = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, windows)?.takeRetainedValue() as? [NSNumber],
              let first = raw.first else {
            return nil
        }
        return first.uint64Value
    }
}
