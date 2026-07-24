import AppKit
import ApplicationServices

/// Wrapper of the application AXUIElement (per-pid).
final class AXApplication {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?

    init(pid: pid_t) {
        self.pid = pid
        self.element = AXUIElementCreateApplication(pid)
        self.bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Current windows of the app (AXWindow role only).
    func windows() -> [AXWindow] {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let array = value as? [AXUIElement] else { return [] }
        return array.compactMap { AXWindow(element: $0, pid: pid) }
    }

    var focusedWindow: AXWindow? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        guard err == .success, let value else { return nil }
        return AXWindow(element: value as! AXUIElement, pid: pid)
    }

    /// Animation bug: if AXEnhancedUserInterface is active, set-frames
    /// are animated/clamped badly. To be disabled during batches.
    var enhancedUserInterface: Bool {
        get {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXEnhancedUserInterface" as CFString, &value)
            return (value as? Bool) ?? false
        }
        set {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString,
                                         newValue ? kCFBooleanTrue : kCFBooleanFalse)
        }
    }

    /// Electron: forces the construction of the AX tree when it is empty.
    func pokeManualAccessibility() {
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Checks that the app responds to AX requests (just-launched apps
    /// respond kAXErrorCannotComplete for a while).
    var isReady: Bool {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        return err == .success || err == .noValue
    }
}
