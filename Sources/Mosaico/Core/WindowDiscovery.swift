import AppKit

/// Initial scan and reconciliation with CGWindowList.
enum WindowDiscovery {

    /// Apps candidate for tiling (regular policy, not us).
    static func tileableApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    }

    /// All existing CGWindowIDs (every space, even off-screen). The window
    /// server is authoritative on the EXISTENCE of a window — unlike
    /// AX, which at wake transiently reports windows as invalid.
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

    /// One-shot capture of the window server state: on-screen layer-0
    /// windows with owner and bounds. ONE CGWindowList call feeds the whole
    /// reconciliation pass, and comparing two snapshots tells whether
    /// anything changed at all — the key to keeping idle cost near zero.
    struct WindowSnapshot: Equatable {
        struct Entry: Equatable {
            let id: WindowID
            let pid: pid_t
            let bounds: CGRect
        }
        let entries: [Entry]

        var ids: Set<WindowID> { Set(entries.map(\.id)) }

        func ids(ownedBy pid: pid_t) -> Set<WindowID> {
            Set(entries.filter { $0.pid == pid }.map(\.id))
        }
    }

    static func snapshot() -> WindowSnapshot {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return WindowSnapshot(entries: [])
        }
        var entries: [WindowSnapshot.Entry] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let owner = info[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            entries.append(.init(id: number, pid: pid_t(owner), bounds: bounds))
        }
        entries.sort { $0.id < $1.id }
        return WindowSnapshot(entries: entries)
    }

    /// AX windows of an app with retry/backoff (just-launched apps
    /// respond kAXErrorCannotComplete for a while; Electron has a lazy
    /// AX tree until it is "poked").
    static func windows(of app: NSRunningApplication,
                        attempts: Int = 5,
                        completion: @escaping ([AXWindow]) -> Void) {
        let ax = AXApplication(pid: app.processIdentifier)

        func attempt(_ remaining: Int, delay: TimeInterval) {
            if ax.isReady {
                var windows = ax.windows()
                if windows.isEmpty {
                    // Possibly Electron with a lazy AX tree
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
