import AppKit

protocol MouseManagerDelegate: AnyObject {
    /// Hit-test WITHOUT AX calls (cache): safe from the tap thread.
    func managedWindowCached(at point: CGPoint) -> ManagedWindow?
    func performDrop(source: ManagedWindow, at point: CGPoint)
    func handlePlainDrop(at point: CGPoint)
    func handleDragEnd()
    func updateDropPreview(at point: CGPoint)
    func endDropPreview()
    func adjustRatio(for managed: ManagedWindow, delta: CGVector)
}

/// CGEventTap for: alt+left-drag moves, alt+right-drag resizes,
/// drop zones, mouse_follows_focus.
///
/// The tap runs on a DEDICATED THREAD: if the main thread is busy with
/// layout/AX, the user's clicks must never accumulate latency.
/// No heavy work in the callback: hit-test from cache, everything else
/// dispatched to main.
final class MouseManager {
    weak var delegate: MouseManagerDelegate?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    private enum DragSession {
        case move(ManagedWindow, offset: CGVector)
        case resize(ManagedWindow, lastPoint: CGPoint)
    }
    private var session: DragSession?

    /// True while an alt-drag session (move or resize) is active.
    var isDragging: Bool { session != nil }

    /// Last REAL mouse activity (movement, click, drag): the follows-focus
    /// warp must never fire right after it. Written by the tap thread,
    /// read by main.
    private let activityLock = NSLock()
    private var _lastActivity = Date.distantPast
    private var lastActivity: Date {
        get { activityLock.lock(); defer { activityLock.unlock() }; return _lastActivity }
        set { activityLock.lock(); _lastActivity = newValue; activityLock.unlock() }
    }

    /// Current mouse-down point: the drop zones preview starts only
    /// after a "real" drag (>30pt), not on every click or text selection.
    private var pressPoint: CGPoint?
    private var lastPreviewUpdate = Date.distantPast
    private var lastRatioUpdate = Date.distantPast

    // MARK: - Lifecycle

    func start() {
        guard tapThread == nil else { return }
        let thread = Thread { [weak self] in
            self?.tapThreadMain()
        }
        thread.name = "MosaicoMouseTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    private func tapThreadMain() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<MouseManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: refcon) else {
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        tapRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let rl = tapRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
            CFRunLoopStop(rl)
        }
        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        session = nil
    }

    // MARK: - Event handling (tap thread: fast, no AX unless dragging)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let point = event.location   // CG/AX coordinates
        let altDown = event.flags.contains(.maskAlternate)
        lastActivity = Date()

        switch type {
        case .mouseMoved:
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            pressPoint = point
            guard altDown, let managed = delegate?.managedWindowCached(at: point) else {
                return Unmanaged.passUnretained(event)
            }
            let frame = managed.window.frame
            session = .move(managed, offset: CGVector(dx: point.x - frame.origin.x,
                                                      dy: point.y - frame.origin.y))
            return nil   // swallow

        case .rightMouseDown:
            guard altDown, let managed = delegate?.managedWindowCached(at: point) else {
                return Unmanaged.passUnretained(event)
            }
            session = .resize(managed, lastPoint: point)
            return nil

        case .leftMouseDragged:
            if case .move(let managed, let offset) = session {
                managed.window.setPosition(CGPoint(x: point.x - offset.dx, y: point.y - offset.dy))
                schedulePreview(at: point)
                return nil
            }
            // Normal drag: preview only after real movement (>30pt)
            if let press = pressPoint, hypot(point.x - press.x, point.y - press.y) > 30 {
                schedulePreview(at: point)
            }
            return Unmanaged.passUnretained(event)

        case .rightMouseDragged:
            guard case .resize(let managed, let lastPoint) = session else {
                return Unmanaged.passUnretained(event)
            }
            let delta = CGVector(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
            session = .resize(managed, lastPoint: point)
            // Ratio on main, throttled to ~30Hz
            if Date().timeIntervalSince(lastRatioUpdate) > 0.033 {
                lastRatioUpdate = Date()
                DispatchQueue.main.async { [weak self] in
                    if managed.isFloating {
                        var size = managed.window.frame.size
                        size.width += delta.dx
                        size.height += delta.dy
                        managed.window.setSize(size)
                    } else {
                        self?.delegate?.adjustRatio(for: managed, delta: delta)
                    }
                }
            }
            return nil

        case .leftMouseUp:
            // Real drag only if the pointer moved: a simple click
            // must not trigger resize adoption (snapping terminals
            // would be adopted on every click).
            let wasDrag = pressPoint.map { hypot(point.x - $0.x, point.y - $0.y) > 6 } ?? false
            pressPoint = nil
            if case .move(let managed, _) = session {
                session = nil
                if !managed.isFloating {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.performDrop(source: managed, at: point)
                        self?.delegate?.endDropPreview()
                        self?.delegate?.handleDragEnd()
                    }
                }
                return nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.handlePlainDrop(at: point)
                self?.delegate?.endDropPreview()
                if wasDrag { self?.delegate?.handleDragEnd() }
            }
            return Unmanaged.passUnretained(event)

        case .rightMouseUp:
            guard case .resize = session else {
                return Unmanaged.passUnretained(event)
            }
            session = nil
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.handleDragEnd()
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Drop zones preview on main, throttled to ~15Hz.
    private func schedulePreview(at point: CGPoint) {
        guard Date().timeIntervalSince(lastPreviewUpdate) > 0.066 else { return }
        lastPreviewUpdate = Date()
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.updateDropPreview(at: point)
        }
    }

    // MARK: - Mouse follows focus

    /// Moves the cursor to the center of the focused window, if enabled.
    /// Never during drag, never with a button held, never right after real
    /// mouse activity (clicks included — otherwise the warp steals the pointer).
    func followFocus(to window: AXWindow) {
        guard SettingsStore.shared.settings.mouseFollowsFocus,
              session == nil,
              NSEvent.pressedMouseButtons == 0,
              Date().timeIntervalSince(lastActivity) > 0.3 else { return }

        let frame = window.frame
        guard frame.width > 0 else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)

        var mouse = NSEvent.mouseLocation
        mouse.y = (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y
        guard !frame.contains(mouse) else { return }

        CGWarpMouseCursorPosition(center)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
