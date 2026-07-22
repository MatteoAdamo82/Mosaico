import AppKit

/// Coordinatore centrale: discovery, eventi, comandi, layout.
final class WindowManager {
    static let shared = WindowManager()

    private let workspaceManager = WorkspaceManager()
    private let observerCenter = AXObserverCenter()
    private let lifecycle = AppLifecycleObserver()
    private let hotkeys = HotkeyManager()
    private let mouse = MouseManager()

    private var reconcileTimer: Timer?
    private var isPaused = false
    private var started = false

    /// Ultima finestra gestita che ha avuto il focus, e la precedente:
    /// quando si apre una finestra nuova (che riceve subito il focus),
    /// l'insert deve splittare quella focussata PRIMA — è questo che
    /// produce il layout a spirale di yabai.
    private var focusedWindowID: WindowID?
    private var previousFocusedWindowID: WindowID?

    /// Debounce dei resize/move manuali per finestra.
    private var pendingAdjustments: [WindowID: DispatchWorkItem] = [:]

    private func noteFocus(_ id: WindowID) {
        guard id != focusedWindowID else { return }
        previousFocusedWindowID = focusedWindowID
        focusedWindowID = id
    }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        workspaceManager.syncDisplays()

        // Eventi AX
        observerCenter.onEvent = { [weak self] pid, notification, element in
            self?.handleAXEvent(pid: pid, notification: notification, element: element)
        }

        // Lifecycle app
        lifecycle.onAppLaunched = { [weak self] app in
            self?.adopt(app: app)
        }
        lifecycle.onAppTerminated = { [weak self] app in
            self?.removeApp(pid: app.processIdentifier)
        }
        lifecycle.onAppActivated = { [weak self] app in
            self?.handleAppActivated(app)
        }
        lifecycle.onDisplaysChanged = { [weak self] in
            guard let self else { return }
            self.workspaceManager.syncDisplays()
            self.retileAll()
        }
        lifecycle.onSpaceChanged = { [weak self] in
            self?.handleSpaceChanged()
        }
        lifecycle.start()

        // Scan iniziale
        for app in WindowDiscovery.tileableApps() {
            adopt(app: app)
        }
        updateSpaceIndicator()

        // Cattura il focus iniziale quando lo scan è assestato
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self,
                  let app = NSWorkspace.shared.frontmostApplication,
                  let window = AXApplication(pid: app.processIdentifier).focusedWindow,
                  self.workspaceManager.locate(window.id) != nil else { return }
            self.noteFocus(window.id)
        }

        // Hotkeys e mouse
        hotkeys.onCommand = { [weak self] command in
            self?.perform(command)
        }
        hotkeys.register(SettingsStore.shared.settings.bindings)
        mouse.delegate = self
        mouse.start()

        // Riconciliazione periodica: auto-ripara eventi persi
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.reconcile()
        }

        // Settings cambiati → re-registra hotkey e retile
        NotificationCenter.default.addObserver(forName: .mosaicoSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.hotkeys.register(SettingsStore.shared.settings.bindings)
            self.retileAll()
        }
    }

    func stop() {
        reconcileTimer?.invalidate()
        observerCenter.stopAll()
        lifecycle.stop()
        hotkeys.unregisterAll()
        mouse.stop()
        started = false
    }

    // MARK: - Adozione app/finestre

    private func adopt(app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        observerCenter.observe(pid: app.processIdentifier)

        WindowDiscovery.windows(of: app) { [weak self] windows in
            guard let self else { return }
            for window in windows {
                self.manage(window: window, bundleID: app.bundleIdentifier)
            }
        }
    }

    /// Inserisce una finestra nel workspace attivo dello SPACE NATIVO su cui
    /// vive (non in quello visibile): le finestre di altri space non toccano
    /// il layout corrente.
    private func manage(window: AXWindow, bundleID: String?) {
        guard workspaceManager.locate(window.id) == nil else { return }

        // Mouse premuto = probabile drag in corso (es. tab del Finder
        // strappata in una finestra nuova): rimanda finché non rilascia.
        if NSEvent.pressedMouseButtons != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.manage(window: window, bundleID: bundleID)
            }
            return
        }

        let disposition = RulesEngine.disposition(for: window, bundleID: bundleID)
        guard disposition != .ignore else { return }

        guard let screen = DisplayManager.screen(containingAX: window.frame) else { return }
        let displayID = DisplayManager.displayID(of: screen)
        let spaceID = SpaceTracker.space(of: window.id)
            ?? SpaceTracker.currentSpace(for: screen) ?? 0

        let spaceState = workspaceManager.spaceState(displayID: displayID, spaceID: spaceID)
        let workspace = spaceState.workspace
        let managed = ManagedWindow(window: window)

        if disposition == .float {
            managed.isFloating = true
            workspace.add(managed, near: nil, leafRect: { _ in nil })
            return   // le float restano dove sono
        }

        workspace.add(managed, near: insertionAnchor(in: workspace, excluding: window.id), leafRect: { [weak self] id in
            self?.frameOfLeaf(id, in: workspace)
        })
        MosaicoLog.log("manage [\(window.id)] '\(window.title ?? "?")' → space \(spaceID) ws \(workspace.index) (n=\(workspace.tree.count))")
        applyLayout(workspace: workspace, screen: screen)
    }

    /// Foglia da splittare per una finestra nuova: la focussata, o la
    /// focussata precedente se la nuova ha già preso il focus.
    private func insertionAnchor(in workspace: Workspace, excluding newID: WindowID) -> WindowID? {
        for candidate in [focusedWindowID, previousFocusedWindowID] {
            if let id = candidate, id != newID, workspace.tree.contains(id) {
                return id
            }
        }
        return nil
    }

    private func frameOfLeaf(_ id: WindowID, in workspace: Workspace) -> CGRect? {
        workspace.windows[id]?.window.frame
    }

    private func removeApp(pid: pid_t) {
        observerCenter.stopObserving(pid: pid)
        var touched: [Workspace] = []
        for (_, display) in workspaceManager.displays {
            for (_, spaceState) in display.spaces {
                let ws = spaceState.workspace
                let ids = ws.windows.values.filter { $0.window.pid == pid }.map(\.id)
                guard !ids.isEmpty else { continue }
                for id in ids { ws.remove(id) }
                touched.append(ws)
            }
        }
        for ws in touched {
            applyLayoutIfVisible(ws)
        }
    }

    private func remove(windowID: WindowID) {
        guard let loc = workspaceManager.locate(windowID) else { return }
        loc.workspace.remove(windowID)
        if focusedWindowID == windowID { focusedWindowID = nil }
        applyLayoutIfVisible(loc.workspace)
    }

    // MARK: - Eventi AX

    private func handleAXEvent(pid: pid_t, notification: String, element: AXUIElement) {
        guard !isPaused else { return }

        switch notification {
        case kAXWindowCreatedNotification:
            guard let window = AXWindow(element: element, pid: pid) else { return }
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            // Piccolo delay: subito dopo la creazione role/subrole a volte non sono pronti
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.manage(window: window, bundleID: bundleID)
            }

        case kAXUIElementDestroyedNotification:
            pruneInvalidWindows()

        case kAXFocusedWindowChangedNotification:
            guard let window = AXWindow(element: element, pid: pid) else { return }
            handleFocusChange(window)

        case kAXWindowMiniaturizedNotification:
            guard let window = AXWindow(element: element, pid: pid) else { return }
            remove(windowID: window.id)

        case kAXWindowDeminiaturizedNotification:
            guard let window = AXWindow(element: element, pid: pid) else { return }
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            manage(window: window, bundleID: bundleID)

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let window = AXWindow(element: element, pid: pid) else { return }
            scheduleManualAdjustment(for: window)

        default:
            break
        }
    }

    /// Resize/move manuale (senza modificatore): debounce, poi il resize
    /// viene adottato nei ratio (le vicine seguono) e il move viene
    /// riportato al layout (snap back).
    private func scheduleManualAdjustment(for window: AXWindow) {
        let id = window.id
        pendingAdjustments[id]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingAdjustments[id] = nil
            // Tasto mouse ancora premuto = drag in corso: riprova dopo
            if NSEvent.pressedMouseButtons != 0 {
                if let loc = self.workspaceManager.locate(id) {
                    self.scheduleManualAdjustment(for: loc.managed.window)
                }
                return
            }
            guard !self.isPaused,
                  !self.mouse.isDragging,
                  let loc = self.workspaceManager.locate(id),
                  !loc.managed.isFloating, !loc.managed.isZoomed,
                  self.workspaceManager.isVisible(loc.workspace),
                  let screen = DisplayManager.screen(withDisplayID: loc.display.displayID) else { return }

            let rect = LayoutEngine.workspaceRect(for: screen)
            let gap = CGFloat(SettingsStore.shared.settings.gap)
            guard let expected = loc.workspace.tree.frames(in: rect, gap: gap)[id] else { return }

            let actual = loc.managed.window.frame
            guard !LayoutEngine.rectsEqual(actual, expected) else { return }

            MosaicoLog.log("adjust [\(id)] expected=\(expected) actual=\(actual)")
            loc.workspace.tree.adoptFrame(for: id, actual: actual, in: rect, gap: gap)
            self.applyLayout(workspace: loc.workspace, screen: screen)
        }

        pendingAdjustments[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func handleFocusChange(_ window: AXWindow) {
        guard workspaceManager.locate(window.id) != nil else { return }
        noteFocus(window.id)
        mouse.followFocus(to: window)
    }

    private func handleAppActivated(_ app: NSRunningApplication) {
        guard !isPaused else { return }
        let ax = AXApplication(pid: app.processIdentifier)
        guard let window = ax.focusedWindow else { return }
        handleFocusChange(window)
    }

    /// L'utente ha cambiato space nativo (Mission Control / Ctrl+freccia):
    /// aggiorna indicatore e ripara lo space appena diventato visibile.
    private func handleSpaceChanged() {
        guard !isPaused else { return }
        MosaicoLog.log("space nativo cambiato")
        updateSpaceIndicator()
        for screen in NSScreen.screens {
            applyLayout(workspace: workspaceManager.activeWorkspace(for: screen), screen: screen)
        }
        // Adotta eventuali finestre nuove di questo space sfuggite agli eventi
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.reconcile()
        }
    }

    /// Indicatore menubar: numero ordinale dello space nativo corrente.
    private func updateSpaceIndicator() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, let ordinal = SpaceTracker.currentSpaceOrdinal(for: screen) else { return }
        MenuState.shared.activeWorkspace = ordinal.current
    }

    /// Rimuove le finestre il cui AXUIElement non risponde più.
    private func pruneInvalidWindows() {
        var toRemove: [WindowID] = []
        for (_, display) in workspaceManager.displays {
            for (_, spaceState) in display.spaces {
                for (id, managed) in spaceState.workspace.windows where !managed.window.isValid {
                    toRemove.append(id)
                }
            }
        }
        for id in toRemove { remove(windowID: id) }
    }

    // MARK: - Riconciliazione

    /// Auto-riparazione: rimuove finestre morte, ricolloca quelle spostate
    /// di space, adotta le nuove, ripristina il layout visibile.
    private func reconcile() {
        guard !isPaused, started else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }

        // 1. Rimuovi finestre morte
        pruneInvalidWindows()

        // 2. Ricolloca finestre spostate su un altro space nativo
        //    (es. trascinate in Mission Control)
        var relocations: [(WindowID, AXWindow, String?)] = []
        for (_, display) in workspaceManager.displays {
            for (storedSpaceID, spaceState) in display.spaces {
                for (id, managed) in spaceState.workspace.windows {
                    guard let actualSpace = SpaceTracker.space(of: id),
                          actualSpace != storedSpaceID else { continue }
                    let bundleID = NSRunningApplication(processIdentifier: managed.window.pid)?.bundleIdentifier
                    relocations.append((id, managed.window, bundleID))
                }
            }
        }
        for (id, window, bundleID) in relocations {
            MosaicoLog.log("ricolloca [\(id)] su nuovo space")
            remove(windowID: id)
            manage(window: window, bundleID: bundleID)
        }

        // 3. Adotta finestre nuove sfuggite agli eventi
        for app in WindowDiscovery.tileableApps() {
            let ax = AXApplication(pid: app.processIdentifier)
            for window in ax.windows() where workspaceManager.locate(window.id) == nil {
                manage(window: window, bundleID: app.bundleIdentifier)
            }
        }

        // 4. Ripristina il layout degli space visibili
        for screen in NSScreen.screens {
            applyLayout(workspace: workspaceManager.activeWorkspace(for: screen), screen: screen)
        }
    }

    // MARK: - Layout

    /// Applica il layout SOLO se il workspace è quello visibile
    /// (space nativo corrente + workspace virtuale attivo).
    private func applyLayout(workspace: Workspace, screen: NSScreen) {
        guard !isPaused, workspaceManager.isVisible(workspace) else { return }
        LayoutEngine.apply(workspace: workspace, on: screen)
        rebuildHitTestCache()
    }

    private func applyLayoutIfVisible(_ workspace: Workspace) {
        guard workspaceManager.isVisible(workspace) else { return }
        for (displayID, display) in workspaceManager.displays {
            for (_, spaceState) in display.spaces {
                guard spaceState.workspace === workspace,
                      let screen = DisplayManager.screen(withDisplayID: displayID) else { continue }
                applyLayout(workspace: workspace, screen: screen)
                return
            }
        }
    }

    func retileAll() {
        for screen in NSScreen.screens {
            applyLayout(workspace: workspaceManager.activeWorkspace(for: screen), screen: screen)
        }
    }

    // MARK: - Comandi

    func perform(_ command: Command) {
        switch command {
        case .pauseResume:
            isPaused.toggle()
            MenuState.shared.isPaused = isPaused
            if !isPaused { reconcile() }
            return
        case .retileAll:
            isPaused = false
            MenuState.shared.isPaused = false
            reconcile()
            return
        default:
            break
        }

        guard !isPaused else { return }

        switch command {
        case .focus(let direction):
            focusNeighbor(direction)

        case .focusDisplay(let direction):
            focusDisplay(direction)

        case .swap(let direction):
            withFocusedTiled { workspace, screen, id in
                guard let neighborID = self.neighbor(of: id, in: workspace, screen: screen, direction: direction) else { return }
                workspace.tree.swap(id, neighborID)
                self.applyLayout(workspace: workspace, screen: screen)
            }

        case .warp(let direction):
            withFocusedTiled { workspace, screen, id in
                guard let neighborID = self.neighbor(of: id, in: workspace, screen: screen, direction: direction) else { return }
                workspace.tree.warp(id, onto: neighborID, direction: direction)
                self.applyLayout(workspace: workspace, screen: screen)
            }

        case .rotate:
            withVisibleWorkspace { workspace, screen in
                workspace.tree.rotate270()
                self.applyLayout(workspace: workspace, screen: screen)
            }

        case .mirrorX:
            withVisibleWorkspace { workspace, screen in
                workspace.tree.mirrorX()
                self.applyLayout(workspace: workspace, screen: screen)
            }

        case .mirrorY:
            withVisibleWorkspace { workspace, screen in
                workspace.tree.mirrorY()
                self.applyLayout(workspace: workspace, screen: screen)
            }

        case .balance:
            withVisibleWorkspace { workspace, screen in
                workspace.tree.balance()
                self.applyLayout(workspace: workspace, screen: screen)
            }

        case .toggleFloat:
            toggleFloat()

        case .toggleZoom:
            toggleZoom()

        case .moveToDisplay(let direction):
            moveToDisplay(direction)

        case .moveToWorkspace(let n):
            moveToNativeSpace(n)

        case .moveToWorkspacePrev, .moveToWorkspaceNext:
            guard let screen = NSScreen.main ?? NSScreen.screens.first,
                  let ordinal = SpaceTracker.currentSpaceOrdinal(for: screen) else { return }
            let delta = (command == .moveToWorkspacePrev) ? -1 : 1
            var target = ordinal.current + delta
            if target < 1 { target = ordinal.total }
            if target > ordinal.total { target = 1 }
            moveToNativeSpace(target)

        case .switchWorkspace(let n):
            // Delega a Mission Control (richiede gli shortcut Ctrl+N attivi
            // in Impostazioni di Sistema → Tastiera → Mission Control)
            if let key = EventPoster.digitKeyCode(n) {
                EventPoster.postCtrlKey(key)
            }

        case .pauseResume, .retileAll:
            break
        }
    }

    // MARK: - Helper comandi

    private func focusedLocation() -> WorkspaceManager.Location? {
        guard let id = currentFocusedID() else { return nil }
        return workspaceManager.locate(id)
    }

    /// ID della finestra focused di sistema (non solo l'ultima tracciata).
    private func currentFocusedID() -> WindowID? {
        if let app = NSWorkspace.shared.frontmostApplication {
            let ax = AXApplication(pid: app.processIdentifier)
            if let window = ax.focusedWindow, workspaceManager.locate(window.id) != nil {
                noteFocus(window.id)
                return window.id
            }
        }
        return focusedWindowID
    }

    private func withFocusedTiled(_ body: (Workspace, NSScreen, WindowID) -> Void) {
        guard let loc = focusedLocation(),
              !loc.managed.isFloating,
              let screen = DisplayManager.screen(withDisplayID: loc.display.displayID) else { return }
        body(loc.workspace, screen, loc.managed.id)
    }

    private func withVisibleWorkspace(_ body: (Workspace, NSScreen) -> Void) {
        if let loc = focusedLocation(),
           let screen = DisplayManager.screen(withDisplayID: loc.display.displayID),
           workspaceManager.isVisible(loc.workspace) {
            body(loc.workspace, screen)
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        body(workspaceManager.activeWorkspace(for: screen), screen)
    }

    /// Vicino geometrico nella direzione, per centro (stile yabai).
    private func neighbor(of id: WindowID, in workspace: Workspace, screen: NSScreen, direction: Direction) -> WindowID? {
        let rect = LayoutEngine.workspaceRect(for: screen)
        let gap = CGFloat(SettingsStore.shared.settings.gap)
        let frames = workspace.tree.frames(in: rect, gap: gap)
        guard let origin = frames[id] else { return nil }
        let center = CGPoint(x: origin.midX, y: origin.midY)

        var best: (WindowID, CGFloat)?
        for (otherID, frame) in frames where otherID != id {
            let otherCenter = CGPoint(x: frame.midX, y: frame.midY)
            let matches: Bool
            switch direction {
            case .west:  matches = otherCenter.x < center.x
            case .east:  matches = otherCenter.x > center.x
            case .north: matches = otherCenter.y < center.y
            case .south: matches = otherCenter.y > center.y
            }
            guard matches else { continue }
            let dx = otherCenter.x - center.x
            let dy = otherCenter.y - center.y
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.1 {
                best = (otherID, distance)
            }
        }
        return best?.0
    }

    private func focusNeighbor(_ direction: Direction) {
        guard let loc = focusedLocation(),
              let screen = DisplayManager.screen(withDisplayID: loc.display.displayID) else { return }

        if !loc.managed.isFloating,
           let neighborID = neighbor(of: loc.managed.id, in: loc.workspace, screen: screen, direction: direction),
           let target = loc.workspace.windows[neighborID] {
            target.window.focus()
            noteFocus(neighborID)
            mouse.followFocus(to: target.window)
        }
    }

    private func focusDisplay(_ direction: Direction) {
        let currentScreen: NSScreen
        if let loc = focusedLocation(),
           let screen = DisplayManager.screen(withDisplayID: loc.display.displayID) {
            currentScreen = screen
        } else {
            currentScreen = NSScreen.main ?? NSScreen.screens[0]
        }

        guard let targetScreen = DisplayManager.screen(direction, of: currentScreen) else { return }
        let workspace = workspaceManager.activeWorkspace(for: targetScreen)

        if let first = workspace.tree.windowIDs.first,
           let managed = workspace.windows[first] {
            managed.window.focus()
            noteFocus(first)
            mouse.followFocus(to: managed.window)
        }
    }

    private func toggleFloat() {
        guard let loc = focusedLocation(),
              let screen = DisplayManager.screen(withDisplayID: loc.display.displayID) else { return }

        if loc.managed.isFloating {
            loc.workspace.setFloating(loc.managed.id, false)
        } else {
            loc.workspace.setFloating(loc.managed.id, true)
            loc.managed.window.setFrame(LayoutEngine.floatFrame(for: screen))
        }
        applyLayout(workspace: loc.workspace, screen: screen)
    }

    private func toggleZoom() {
        guard let loc = focusedLocation(),
              !loc.managed.isFloating,
              let screen = DisplayManager.screen(withDisplayID: loc.display.displayID) else { return }
        loc.managed.isZoomed.toggle()
        applyLayout(workspace: loc.workspace, screen: screen)
        if loc.managed.isZoomed {
            loc.managed.window.focus()
        }
    }

    private func moveToDisplay(_ direction: Direction) {
        guard let loc = focusedLocation(),
              let sourceScreen = DisplayManager.screen(withDisplayID: loc.display.displayID),
              let targetScreen = DisplayManager.screen(direction, of: sourceScreen) else { return }

        loc.workspace.remove(loc.managed.id)
        applyLayout(workspace: loc.workspace, screen: sourceScreen)

        let targetWorkspace = workspaceManager.activeWorkspace(for: targetScreen)
        targetWorkspace.add(loc.managed, near: nil, leafRect: { [weak self] id in
            self?.frameOfLeaf(id, in: targetWorkspace)
        })
        applyLayout(workspace: targetWorkspace, screen: targetScreen)

        loc.managed.window.focus()
        mouse.followFocus(to: loc.managed.window)
    }

    /// Sposta la finestra focussata su uno space nativo: la "afferra" con un
    /// mouse-down simulato sulla titlebar, cambia space con Ctrl+N (Mission
    /// Control trasporta la finestra afferrata), poi rilascia. Stessa tecnica
    /// usata da yabai senza scripting addition.
    private func moveToNativeSpace(_ number: Int) {
        guard let loc = focusedLocation(),
              let screen = DisplayManager.screen(withDisplayID: loc.display.displayID),
              let key = EventPoster.digitKeyCode(number),
              let ordinal = SpaceTracker.currentSpaceOrdinal(for: screen),
              number != ordinal.current, number <= ordinal.total else { return }

        let window = loc.managed.window
        let frame = window.frame
        let grabPoint = CGPoint(x: frame.midX, y: frame.minY + 8)   // titlebar

        MosaicoLog.log("moveToNativeSpace [\(window.id)] → space \(number)")

        // Fuori dal tree subito, così il vecchio space si ricompatta
        loc.workspace.remove(loc.managed.id)
        applyLayoutIfVisible(loc.workspace)

        window.focus()
        EventPoster.postMouse(.leftMouseDown, at: grabPoint)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            EventPoster.postCtrlKey(key)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                EventPoster.postMouse(.leftMouseUp, at: grabPoint)
                // La riconciliazione ricolloca la finestra nel tree del nuovo space
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.reconcile()
                }
            }
        }
    }

    // MARK: - Esclusione finestre specifiche

    struct WindowInfo: Identifiable {
        let id: WindowID
        let title: String
        let appName: String
        let bundleID: String?
    }

    /// Snapshot delle finestre gestite (per il menu "Escludi finestra").
    func managedWindowsSnapshot() -> [WindowInfo] {
        var result: [WindowInfo] = []
        for (_, display) in workspaceManager.displays {
            for (_, spaceState) in display.spaces {
                for (id, managed) in spaceState.workspace.windows {
                    let app = NSRunningApplication(processIdentifier: managed.window.pid)
                    result.append(WindowInfo(id: id,
                                             title: managed.window.title ?? "(senza titolo)",
                                             appName: app?.localizedName ?? "?",
                                             bundleID: app?.bundleIdentifier))
                }
            }
        }
        return result.sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    /// Esclude una finestra specifica: regola persistente (app + titolo)
    /// e rimozione immediata dal tiling.
    func excludeWindow(_ id: WindowID) {
        guard let loc = workspaceManager.locate(id) else { return }
        if let bundleID = NSRunningApplication(processIdentifier: loc.managed.window.pid)?.bundleIdentifier,
           let title = loc.managed.window.title, !title.isEmpty {
            var settings = SettingsStore.shared.settings
            let rule = WindowRule(bundleID: bundleID, title: title)
            if !settings.excludedWindowRules.contains(rule) {
                settings.excludedWindowRules.append(rule)
                SettingsStore.shared.settings = settings
            }
            MosaicoLog.log("esclusa finestra [\(id)] \(rule.bundleID) '\(rule.title)'")
        }
        remove(windowID: id)
    }

    // MARK: - Drop zones (stile yabai)

    private enum DropKind {
        case swap(WindowID)
        case warp(WindowID, Direction)
    }

    private struct DropResolution {
        let workspace: Workspace
        let screen: NSScreen
        let kind: DropKind
        let highlight: CGRect   // rect da evidenziare, coordinate AX
    }

    /// La finestra che l'utente sta trascinando: tiled, frame reale che
    /// contiene il cursore, origine lontana dal layout ma STESSE dimensioni —
    /// un resize cambia le dimensioni e NON è un drag.
    private func findDragSource(at point: CGPoint) -> ManagedWindow? {
        let gap = CGFloat(SettingsStore.shared.settings.gap)
        var best: (ManagedWindow, CGFloat)?
        for screen in NSScreen.screens {
            let workspace = workspaceManager.activeWorkspace(for: screen)
            let frames = workspace.tree.frames(in: LayoutEngine.workspaceRect(for: screen), gap: gap)
            for (id, expected) in frames {
                guard let managed = workspace.windows[id], !managed.isFloating, !managed.isZoomed else { continue }
                let actual = managed.window.frame
                guard actual.contains(point) else { continue }
                guard abs(actual.width - expected.width) < 10,
                      abs(actual.height - expected.height) < 10 else { continue }
                let mismatch = abs(actual.origin.x - expected.origin.x) + abs(actual.origin.y - expected.origin.y)
                if mismatch > 15, best == nil || mismatch > best!.1 {
                    best = (managed, mismatch)
                }
            }
        }
        return best?.0
    }

    /// Zone: centro (30–70%) → swap; metà → warp nella direzione.
    private func resolveDrop(source: ManagedWindow, at point: CGPoint) -> DropResolution? {
        guard let screen = DisplayManager.screen(containingAX: point) else { return nil }
        let workspace = workspaceManager.activeWorkspace(for: screen)
        let rect = LayoutEngine.workspaceRect(for: screen)
        let gap = CGFloat(SettingsStore.shared.settings.gap)
        let frames = workspace.tree.frames(in: rect, gap: gap)

        var target: (WindowID, CGRect)?
        for (id, frame) in frames where id != source.id && frame.contains(point) {
            target = (id, frame)
        }
        guard let (targetID, tf) = target else { return nil }

        let rx = (point.x - tf.minX) / tf.width
        let ry = (point.y - tf.minY) / tf.height

        if (0.3...0.7).contains(rx) && (0.3...0.7).contains(ry) {
            return DropResolution(workspace: workspace, screen: screen,
                                  kind: .swap(targetID), highlight: tf)
        }
        if abs(rx - 0.5) > abs(ry - 0.5) {
            let direction: Direction = rx < 0.5 ? .west : .east
            var half = tf
            half.size.width /= 2
            if direction == .east { half.origin.x = tf.midX }
            return DropResolution(workspace: workspace, screen: screen,
                                  kind: .warp(targetID, direction), highlight: half)
        }
        let direction: Direction = ry < 0.5 ? .north : .south
        var half = tf
        half.size.height /= 2
        if direction == .south { half.origin.y = tf.midY }
        return DropResolution(workspace: workspace, screen: screen,
                              kind: .warp(targetID, direction), highlight: half)
    }

    /// Preview live durante il drag: evidenzia la zona di drop.
    func updateDropPreview(at point: CGPoint) {
        guard !isPaused,
              let source = findDragSource(at: point),
              let resolution = resolveDrop(source: source, at: point) else {
            DropZoneOverlay.shared.hide()
            return
        }
        DropZoneOverlay.shared.show(axRect: resolution.highlight)
    }

    func endDropPreview() {
        DropZoneOverlay.shared.hide()
    }

    /// Applica il drop (anche tra display: la finestra migra nel workspace
    /// visibile del display di destinazione).
    func performDrop(source: ManagedWindow, at point: CGPoint) {
        DropZoneOverlay.shared.hide()

        guard let sourceLoc = workspaceManager.locate(source.id),
              !source.isFloating else { return }

        pendingAdjustments[source.id]?.cancel()
        pendingAdjustments[source.id] = nil

        guard let resolution = resolveDrop(source: source, at: point) else {
            MosaicoLog.log("drop [\(source.id)] nessun target → snap back")
            applyLayoutIfVisible(sourceLoc.workspace)
            return
        }
        MosaicoLog.log("drop [\(source.id)] \(resolution.kind) point=\(point)")

        if resolution.workspace !== sourceLoc.workspace {
            sourceLoc.workspace.remove(source.id)
            applyLayoutIfVisible(sourceLoc.workspace)
            resolution.workspace.add(source, near: nil, leafRect: { [weak self] id in
                self?.frameOfLeaf(id, in: resolution.workspace)
            })
        }

        switch resolution.kind {
        case .swap(let targetID):
            resolution.workspace.tree.swap(source.id, targetID)
        case .warp(let targetID, let direction):
            resolution.workspace.tree.warp(source.id, onto: targetID, direction: direction)
        }
        applyLayout(workspace: resolution.workspace, screen: resolution.screen)
    }

    /// Drop da drag normale (senza ⌥).
    func handlePlainDrop(at point: CGPoint) {
        guard !isPaused else { return }
        DropZoneOverlay.shared.hide()
        guard let source = findDragSource(at: point) else { return }
        performDrop(source: source, at: point)
    }

    /// Fine di qualsiasi gesto mouse: adotta i resize fatti a mano
    /// (senza dipendere dalle notifiche AX, che Electron & co. non emettono)
    /// e riporta al layout le finestre solo spostate.
    func handleDragEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isPaused, NSEvent.pressedMouseButtons == 0 else { return }
            let gap = CGFloat(SettingsStore.shared.settings.gap)
            for screen in NSScreen.screens {
                let workspace = self.workspaceManager.activeWorkspace(for: screen)
                let rect = LayoutEngine.workspaceRect(for: screen)
                var frames = workspace.tree.frames(in: rect, gap: gap)
                var needsApply = false
                for (id, expected) in frames {
                    guard let managed = workspace.windows[id], !managed.isFloating, !managed.isZoomed else { continue }
                    let actual = managed.window.frame
                    if abs(actual.width - expected.width) > 6 || abs(actual.height - expected.height) > 6 {
                        MosaicoLog.log("dragEnd adopt [\(id)] expected=\(expected) actual=\(actual)")
                        workspace.tree.adoptFrame(for: id, actual: actual, in: rect, gap: gap)
                        frames = workspace.tree.frames(in: rect, gap: gap)
                        needsApply = true
                    } else if !LayoutEngine.rectsEqual(actual, expected) {
                        MosaicoLog.log("dragEnd snapback [\(id)] actual=\(actual)")
                        needsApply = true
                    }
                }
                if needsApply {
                    self.applyLayout(workspace: workspace, screen: screen)
                }
            }
        }
    }

    // MARK: - Accesso per MouseManager

    /// Cache per l'hit-test dal thread del tap: (frame, finestra) degli
    /// workspace visibili. Ricostruita a ogni applyLayout/reconcile sul main;
    /// letta dal thread del mouse senza chiamate AX.
    private let hitTestLock = NSLock()
    private var hitTestEntries: [(frame: CGRect, managed: ManagedWindow)] = []

    private func rebuildHitTestCache() {
        var entries: [(CGRect, ManagedWindow)] = []
        let gap = CGFloat(SettingsStore.shared.settings.gap)
        for screen in NSScreen.screens {
            let workspace = workspaceManager.activeWorkspace(for: screen)
            let frames = workspace.tree.frames(in: LayoutEngine.workspaceRect(for: screen), gap: gap)
            for (id, frame) in frames {
                if let managed = workspace.windows[id] {
                    entries.append((frame, managed))
                }
            }
            for (_, managed) in workspace.windows where managed.isFloating {
                entries.append((managed.window.frame, managed))
            }
        }
        hitTestLock.lock()
        hitTestEntries = entries
        hitTestLock.unlock()
    }

    func managedWindowCached(at point: CGPoint) -> ManagedWindow? {
        hitTestLock.lock()
        defer { hitTestLock.unlock() }
        // Le float per ultime in lista = priorità (stanno sopra)
        return hitTestEntries.last(where: { $0.frame.contains(point) })?.managed
    }

    func adjustRatio(for managed: ManagedWindow, delta: CGVector) {
        guard let loc = workspaceManager.locate(managed.id),
              let screen = DisplayManager.screen(withDisplayID: loc.display.displayID),
              let leaf = loc.workspace.tree.leaf(for: managed.id) else { return }

        let rect = LayoutEngine.workspaceRect(for: screen)

        var node: BSPNode? = leaf
        var didHorizontal = false
        var didVertical = false
        while let current = node?.parent, !(didHorizontal && didVertical) {
            let isFirst = current.first === node
            if current.orientation == .horizontal, !didHorizontal, abs(delta.dx) > 0.5 {
                let span = rect.width
                let change = delta.dx / span * (isFirst ? 1 : -1)
                current.ratio = max(0.1, min(0.9, current.ratio + change))
                didHorizontal = true
            }
            if current.orientation == .vertical, !didVertical, abs(delta.dy) > 0.5 {
                let span = rect.height
                let change = delta.dy / span * (isFirst ? 1 : -1)
                current.ratio = max(0.1, min(0.9, current.ratio + change))
                didVertical = true
            }
            node = current
        }
        applyLayout(workspace: loc.workspace, screen: screen)
    }
}

extension WindowManager: MouseManagerDelegate {}
