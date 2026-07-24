import CoreGraphics
import Carbon.HIToolbox

/// Posting of synthetic mouse/keyboard events (to drive Mission Control:
/// space switching via Ctrl+N and window transport with a simulated drag).
enum EventPoster {

    static func postMouse(_ type: CGEventType, button: CGMouseButton = .left, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Ctrl + key (keycode) — keyDown and keyUp.
    static func postCtrlKey(_ keyCode: CGKeyCode) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = .maskControl
            event.post(tap: .cghidEventTap)
        }
    }

    /// Keycode of digit 1..9 (top row).
    static func digitKeyCode(_ digit: Int) -> CGKeyCode? {
        let codes: [Int: Int] = [
            1: kVK_ANSI_1, 2: kVK_ANSI_2, 3: kVK_ANSI_3, 4: kVK_ANSI_4,
            5: kVK_ANSI_5, 6: kVK_ANSI_6, 7: kVK_ANSI_7, 8: kVK_ANSI_8, 9: kVK_ANSI_9,
        ]
        guard let code = codes[digit] else { return nil }
        return CGKeyCode(code)
    }
}
