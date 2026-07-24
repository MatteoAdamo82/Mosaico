import AppKit

/// Scansione iniziale e riconciliazione con CGWindowList.
enum WindowDiscovery {

    /// App candidate al tiling (policy regular, non noi).
    static func tileableApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    }

    /// Tutti i CGWindowID esistenti (ogni space, anche off-screen). Il window
    /// server è autorevole sull'ESISTENZA di una finestra — a differenza di
    /// AX, che al wake riporta transitoriamente le finestre come invalide.
    static func allWindowIDs() -> Set<WindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<WindowID>()
        for info in list {
            if let number = info[kCGWindowNumber as String] as? UInt32 {
                ids.insert(number)
            }
        }
        return ids
    }

    /// Finestre AX di un'app con retry/backoff (le app appena lanciate
    /// rispondono kAXErrorCannotComplete per un po'; Electron ha l'albero
    /// AX lazy finché non viene "pokato").
    static func windows(of app: NSRunningApplication,
                        attempts: Int = 5,
                        completion: @escaping ([AXWindow]) -> Void) {
        let ax = AXApplication(pid: app.processIdentifier)

        func attempt(_ remaining: Int, delay: TimeInterval) {
            if ax.isReady {
                var windows = ax.windows()
                if windows.isEmpty {
                    // Possibile Electron con AX tree lazy
                    ax.pokeManualAccessibility()
                    windows = ax.windows()
                }
                if !windows.isEmpty || remaining <= 0 {
                    completion(windows)
                    return
                }
            }
            guard remaining > 0 else {
                completion([])
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(remaining - 1, delay: delay * 2)
            }
        }

        attempt(attempts, delay: 0.1)
    }
}
