import AppKit
import QuartzCore

/// Draws the swinging pointer in place of whatever cursor the system is showing.
///
/// One overlay window, sized to the screen the pointer is on and moved when it
/// crosses to another. A full-screen window per display costs several megabytes
/// of backing store each, and only one of them is ever drawing.
final class SwingOverlay {
    private(set) var isEnabled = false

    private var window: NSWindow?
    private var arrow: PointerLayer?
    private var currentScreen: NSScreen?
    private let frames = FrameDriver()
    private var watchdog: Timer?

    private let hider = CursorHider()
    private let shapes = CursorShapeReader()
    private var physics = SwingPhysics()
    private var lastMouse = NSEvent.mouseLocation
    private var systemScale = CGSPrivate.systemCursorScale
    private var lastShapePoll = 0.0
    private var lastScalePoll = 0.0
    private var isSuspended = false

    private var isDrawing: Bool { isEnabled && !isSuspended }

    /// Registered once for the app's lifetime: re-asserting is a no-op unless the
    /// swing is on, and re-registering on every enable stacked duplicates.
    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [NSWorkspace.didActivateApplicationNotification,
                                          NSWorkspace.activeSpaceDidChangeNotification,
                                          NSWorkspace.didWakeNotification] {
            workspace.addObserver(self, selector: #selector(reassertHidden), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        physics.reset()
        shapes.reset()
        lastMouse = NSEvent.mouseLocation
        buildWindow()
        hider.hide()
        startWatchdog()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        hider.show()
        watchdog?.invalidate()
        watchdog = nil
        tearDownWindow()
    }

    /// Give the real pointer back while our settings panel is frontmost.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        hider.suspend(for: .settingsPanel)
        arrow?.isHidden = true
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        hider.resume(for: .settingsPanel)
        lastMouse = NSEvent.mouseLocation
        physics.reset()
    }

    private func buildWindow() {
        tearDownWindow()
        let screen = self.screen(nearest: NSEvent.mouseLocation)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let arrow = PointerLayer()
        arrow.isHidden = true
        view.layer?.addSublayer(arrow)
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.arrow = arrow
        currentScreen = screen
        frames.start(in: window) { [weak self] now, dt in
            self?.step(now: now, dt: dt)
        }
    }

    private func tearDownWindow() {
        frames.stop()
        window?.orderOut(nil)
        window = nil
        arrow = nil
        currentScreen = nil
    }

    /// Nearest, not "the one containing the point": on a screen edge the pointer
    /// belongs to no frame, and a strict test made it vanish and jump there.
    private func screen(nearest point: NSPoint) -> NSScreen {
        NSScreen.screens.min {
            $0.frame.squaredDistance(to: point) < $1.frame.squaredDistance(to: point)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screensChanged() {
        guard isEnabled else { return }
        buildWindow()
    }

    private func step(now: CFTimeInterval, dt: CFTimeInterval) {
        let mouse = NSEvent.mouseLocation
        let delta = CGVector(dx: mouse.x - lastMouse.x, dy: mouse.y - lastMouse.y)
        lastMouse = mouse

        guard isDrawing, let window, let arrow else { return }

        // Counted in seconds, not frames: reading the system cursor costs a
        // millisecond or two, and at 165 Hz a frame is only 6 ms, so an "every
        // 4th frame" rule would poll nearly three times as often on the fast
        // display and eat the budget it was meant to fit inside.
        if now - lastShapePoll >= 0.066 {
            lastShapePoll = now
            shapes.refresh()
        }
        if now - lastScalePoll >= 0.5 {
            lastScalePoll = now
            systemScale = CGSPrivate.systemCursorScale
        }

        // Something we cannot read — a custom cursor, or the spinning wait
        // cursor. Show the genuine article rather than the wrong shape.
        guard shapes.isReadable else {
            arrow.isHidden = true
            hider.suspend(for: .unreadableCursor)
            return
        }
        hider.resume(for: .unreadableCursor)

        physics.track(delta: delta, dt: dt)
        physics.advance(dt: dt, tune: .current, centreOfMass: shapes.shape.centreOfMass)

        followScreen(of: mouse, window: window)
        let origin = window.frame.origin
        arrow.isHidden = false
        arrow.place(shape: shapes.shape,
                    hotSpot: CGPoint(x: mouse.x - origin.x, y: mouse.y - origin.y),
                    angleDeg: physics.angleDeg,
                    scale: arrowScale)
    }

    private func followScreen(of point: NSPoint, window: NSWindow) {
        let screen = self.screen(nearest: point)
        guard screen !== currentScreen else { return }
        currentScreen = screen
        window.setFrame(screen.frame, display: false)
        window.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
    }

    /// 1.00× is the system pointer at its real size; the setting multiplies it.
    private var arrowScale: CGFloat { CGFloat(systemScale * Pref.size.value) }

    /// Anything can put the cursor back on screen, so keep re-hiding it.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.hider.reassert()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    @objc private func reassertHidden() {
        hider.reassert()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.hider.reassert()
        }
    }
}
