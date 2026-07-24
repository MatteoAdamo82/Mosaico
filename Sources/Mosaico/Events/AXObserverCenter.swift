import AppKit
import ApplicationServices

/// One AXObserver per app; all notifications converge on the main run loop
/// and are forwarded to the WindowManager.
final class AXObserverCenter {
    static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    private var observers: [pid_t: AXObserver] = [:]

    var onEvent: ((_ pid: pid_t, _ notification: String, _ element: AXUIElement) -> Void)?

    func observe(pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let center = Unmanaged<AXObserverCenter>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            center.onEvent?(pid, notification as String, element)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, appElement, name as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    func stopObserving(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func stopAll() {
        for pid in Array(observers.keys) {
            stopObserving(pid: pid)
        }
    }
}
