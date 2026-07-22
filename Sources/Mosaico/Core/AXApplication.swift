import AppKit
import ApplicationServices

/// Wrapper dell'AXUIElement applicazione (per-pid).
final class AXApplication {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?

    init(pid: pid_t) {
        self.pid = pid
        self.element = AXUIElementCreateApplication(pid)
        self.bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Finestre correnti dell'app (solo role AXWindow).
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

    /// Bug animazioni: se AXEnhancedUserInterface è attivo, i set-frame
    /// vengono animati/clampati male. Da disattivare durante i batch.
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

    /// Electron: forza la costruzione dell'albero AX quando risulta vuoto.
    func pokeManualAccessibility() {
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Verifica che l'app risponda alle richieste AX (le app appena lanciate
    /// rispondono kAXErrorCannotComplete per un po').
    var isReady: Bool {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        return err == .success || err == .noValue
    }
}
