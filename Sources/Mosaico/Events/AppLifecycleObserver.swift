import AppKit

/// Notifiche NSWorkspace: lancio/chiusura/attivazione app e cambi display.
final class AppLifecycleObserver {
    var onAppLaunched: ((NSRunningApplication) -> Void)?
    var onAppTerminated: ((NSRunningApplication) -> Void)?
    var onAppActivated: ((NSRunningApplication) -> Void)?
    var onDisplaysChanged: (() -> Void)?
    var onSpaceChanged: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    func start() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        tokens.append(wsCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onAppLaunched?(app)
        })

        tokens.append(wsCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onAppTerminated?(app)
        })

        tokens.append(wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onAppActivated?(app)
        })

        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            self?.onDisplaysChanged?()
        })

        // Cambio di space nativo (Mission Control / Ctrl+freccia)
        tokens.append(wsCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            self?.onSpaceChanged?()
        })
    }

    func stop() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for token in tokens {
            wsCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }
}
