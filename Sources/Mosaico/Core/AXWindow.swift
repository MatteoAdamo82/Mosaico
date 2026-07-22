import AppKit
import ApplicationServices
import CAXShim

typealias WindowID = CGWindowID

/// Wrapper di un AXUIElement finestra. Tutte le coordinate in spazio AX
/// (origine alto-sinistra del primario).
final class AXWindow {
    let element: AXUIElement
    let pid: pid_t
    let id: WindowID

    init?(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
        var windowID: CGWindowID = 0
        guard MosaicoGetWindowID(element, &windowID) == .success, windowID != 0 else {
            return nil
        }
        self.id = windowID
    }

    // MARK: - Attributi

    private func copyAttribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return err == .success ? value : nil
    }

    var role: String? {
        copyAttribute(kAXRoleAttribute) as? String
    }

    var subrole: String? {
        copyAttribute(kAXSubroleAttribute) as? String
    }

    var title: String? {
        copyAttribute(kAXTitleAttribute) as? String
    }

    var isMinimized: Bool {
        (copyAttribute(kAXMinimizedAttribute) as? Bool) ?? false
    }

    var isFullscreen: Bool {
        (copyAttribute("AXFullScreen") as? Bool) ?? false
    }

    /// Sheet/dialog agganciati hanno un parent finestra.
    var hasWindowParent: Bool {
        guard let parent = copyAttribute(kAXParentAttribute) else { return false }
        let parentElement = parent as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &role)
        return (role as? String) == kAXWindowRole
    }

    var isResizable: Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        return settable.boolValue
    }

    var isMovable: Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable)
        return settable.boolValue
    }

    var isValid: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
    }

    /// Layer CGWindow: 0 = finestra normale; ≠0 = flottante di sistema
    /// (PiP, palette always-on-top) — mai da tilare.
    var cgLayer: Int {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let info = list.first,
              let layer = info[kCGWindowLayer as String] as? Int else { return 0 }
        return layer
    }

    // MARK: - Frame

    var frame: CGRect {
        get {
            var pos = CGPoint.zero
            var size = CGSize.zero
            if let value = copyAttribute(kAXPositionAttribute) {
                AXValueGetValue(value as! AXValue, .cgPoint, &pos)
            }
            if let value = copyAttribute(kAXSizeAttribute) {
                AXValueGetValue(value as! AXValue, .cgSize, &size)
            }
            return CGRect(origin: pos, size: size)
        }
        set {
            setFrame(newValue)
        }
    }

    /// Trick "set twice" (Rectangle): position → size → size, alcune app
    /// applicano il resize solo dopo il move o lo clampano al primo colpo.
    func setFrame(_ rect: CGRect) {
        setPosition(rect.origin)
        setSize(rect.size)
        let actual = frame
        if abs(actual.width - rect.width) > 1 || abs(actual.height - rect.height) > 1 {
            setSize(rect.size)
        }
        if abs(frame.origin.x - rect.origin.x) > 1 || abs(frame.origin.y - rect.origin.y) > 1 {
            setPosition(rect.origin)
        }
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    // MARK: - Focus

    /// Porta la finestra sopra le altre senza cambiare focus/app attiva.
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func focus() {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}

extension AXWindow: Equatable, Hashable {
    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
