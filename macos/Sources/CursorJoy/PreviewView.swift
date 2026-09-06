import AppKit
import QuartzCore

/// What the preview should illustrate while a control is being used.
enum PreviewGuide {
    /// Two ghosts at the tilt limits.
    case tilt
    /// One ghost where the current speed is pulling the pointer.
    case sensitivity
    /// A fading trail of the recent swing, so the rate and the decay show.
    case wobble
    /// One ghost at 1.00×, to compare the chosen size against.
    case size
    /// One ghost at the mirrored angle: what the other setting would do.
    case invert
}

/// The settings preview. Left alone it strolls between random points, resting
/// long enough between them for the wobble to play out. Hover it and your own
/// pointer takes the wheel, so a setting can be felt as well as seen.
///
/// It runs the real `SwingPhysics` on the real system cursor artwork, so nothing
/// here can flatter the settings.
final class PreviewView: NSView {
    /// Set while a control is being used; nil the rest of the time.
    var guide: PreviewGuide? {
        didSet { if guide != .wobble { trail.removeAll() } }
    }

    /// The preview holds still when the swing is switched off, like the real one.
    var swingEnabled = true

    private let shape = CursorShape.arrow
    private let arrow = PointerLayer()
    private let ghosts = (0..<8).map { _ -> PointerLayer in
        let layer = PointerLayer()
        layer.isHidden = true
        return layer
    }

    private let frames = FrameDriver()
    private var physics = SwingPhysics()
    private var trail: [Double] = []
    private var isDriven = false

    private var from = CGPoint.zero
    private var to = CGPoint.zero
    private var position = CGPoint.zero
    private var legStart = 0.0
    private var legDuration = 1.0
    private var restUntil = 0.0
    private var isWalking = false
    private var laidOutSize = CGSize.zero
    private var closeObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        ghosts.forEach { layer?.addSublayer($0) }
        layer?.addSublayer(arrow)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { stop() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stop() : start()
    }

    override func layout() {
        super.layout()
        // SwiftUI re-lays us out on every slider tick; only a real resize should
        // interrupt the walk.
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        position = CGPoint(x: roamRect.midX, y: roamRect.midY)
        from = position
        to = position
        isWalking = false
    }

    func start() {
        stop()
        guard let window else { return }
        physics.reset()
        restUntil = CACurrentMediaTime() + 0.4
        frames.start(in: window) { [weak self] now, dt in
            self?.step(now: now, dt: dt)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in self?.stop() }
    }

    func stop() {
        frames.stop()
        closeObserver.map(NotificationCenter.default.removeObserver)
        closeObserver = nil
        releasePointer()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isDriven else { return }
        isDriven = true
        physics.reset()
        NSCursor.hide()
    }

    override func mouseExited(with event: NSEvent) {
        releasePointer()
        // Pick the walk back up from wherever the pointer left it.
        from = position
        to = position
        isWalking = false
        restUntil = CACurrentMediaTime() + 0.3
    }

    private func releasePointer() {
        guard isDriven else { return }
        isDriven = false
        NSCursor.unhide()
    }

    private func step(now: CFTimeInterval, dt: CFTimeInterval) {
        let previous = position
        if isDriven, let window {
            // Unclamped: the box clips it, exactly as a screen edge would.
            position = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        } else {
            advanceWalk(now: now)
            position = position.clamped(to: roamRect)
        }

        let tune = SwingTune.current
        physics.track(delta: CGVector(dx: position.x - previous.x, dy: position.y - previous.y),
                      dt: dt)
        physics.advance(dt: dt, tune: tune, centreOfMass: shape.centreOfMass)

        let angle = swingEnabled ? physics.angleDeg : 0
        arrow.place(shape: shape, hotSpot: position, angleDeg: angle, scale: scale)
        placeGuides(tune: tune, angle: angle)
    }

    private func placeGuides(tune: SwingTune, angle: Double) {
        var used = 0

        func ghost(_ angle: Double, opacity: Float, scale: CGFloat = self.scale) {
            guard used < ghosts.count else { return }
            let layer = ghosts[used]
            used += 1
            layer.isHidden = false
            layer.place(shape: shape, hotSpot: position, angleDeg: angle,
                        scale: scale, opacity: opacity)
        }

        switch guide {
        case .tilt:
            ghost(tune.maxAngleDeg, opacity: 0.28)
            ghost(-tune.maxAngleDeg, opacity: 0.28)
        case .sensitivity:
            ghost(physics.restingAngle(tune, centreOfMass: shape.centreOfMass), opacity: 0.35)
        case .wobble:
            trail.append(angle)
            if trail.count > ghosts.count { trail.removeFirst() }
            for (i, past) in trail.enumerated() {
                ghost(past, opacity: Float(0.30 * Double(i + 1) / Double(trail.count)))
            }
        case .size:
            ghost(angle, opacity: 0.3, scale: referenceScale)
        case .invert:
            ghost(-angle, opacity: 0.35)
        case nil:
            break
        }

        for i in used..<ghosts.count { ghosts[i].isHidden = true }
    }

    /// A touch larger than life so the tilt is easy to read in a small box.
    private let referenceScale: CGFloat = 1.35
    private var scale: CGFloat { referenceScale * CGFloat(Pref.size.value) }

    /// Where the hot spot may go without any part of the pointer leaving the box.
    private var roamRect: CGRect {
        let inset = min(shape.reach * scale + 3, min(bounds.width, bounds.height) / 2 - 4)
        return bounds.insetBy(dx: max(inset, 2), dy: max(inset, 2))
    }

    private func advanceWalk(now: CFTimeInterval) {
        guard isWalking else {
            if now >= restUntil { planNextLeg(now: now) }
            return
        }
        let progress = min((now - legStart) / legDuration, 1)
        // Smoothstep: eases out of rest and back into it, so the swing builds and
        // releases instead of snapping.
        let t = progress * progress * (3 - 2 * progress)
        position = CGPoint(x: from.x + (to.x - from.x) * t,
                           y: from.y + (to.y - from.y) * t)
        if progress >= 1 {
            isWalking = false
            restUntil = now + .random(in: 0.5...1.4)
        }
    }

    private func planNextLeg(now: CFTimeInterval) {
        let roam = roamRect
        guard roam.width > 1, roam.height > 1 else { return }

        from = position
        // Aim far enough away that the trip is worth watching.
        let minTravel = 0.35 * min(roam.width, roam.height)
        var target = from
        for _ in 0..<8 {
            target = CGPoint(x: .random(in: roam.minX...roam.maxX),
                             y: .random(in: roam.minY...roam.maxY))
            if hypot(target.x - from.x, target.y - from.y) >= minTravel { break }
        }
        to = target

        legStart = now
        // Points per millisecond, picked fresh for every leg.
        let speed = Double.random(in: 0.15...0.9)
        legDuration = max(0.25, hypot(to.x - from.x, to.y - from.y) / speed / 1000)
        isWalking = true
    }
}
