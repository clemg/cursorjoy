import AppKit
import SwiftUI

/// The one runnable check: the swing model and the shape measurement.
/// Run with CURSORJOY_SELFTEST=1.
func runSelfTest() {
    let tune = SwingTune(gain: 30, maxAngleDeg: 60, frequencyHz: 2.1, damping: 0.32, direction: 1)
    // The plain arrow's mass sits down and to the right of its tip.
    let arrowMass = CursorShape.defaultMass

    /// Flick the pointer along `delta` for 150 ms, then report the peak tilt.
    func flick(_ delta: CGVector, tune: SwingTune, mass: CGVector = arrowMass) -> Double {
        var p = SwingPhysics()
        var peak = 0.0
        for _ in 0..<18 {
            p.track(delta: delta, dt: 1.0 / 120)
            p.advance(dt: 1.0 / 120, tune: tune, centreOfMass: mass)
            if abs(p.angleDeg) > abs(peak) { peak = p.angleDeg }
        }
        return peak
    }

    // Moving right, the body trails to the right of the tip: clockwise, positive.
    let right = flick(CGVector(dx: 8, dy: 0), tune: tune)
    assert(right > 5, "a rightward flick must swing the pointer clockwise, got \(right)")
    assert(flick(CGVector(dx: -8, dy: 0), tune: tune) < -5, "a leftward flick must mirror it")

    // The regression that mattered: vertical moves have to swing it too.
    let up = flick(CGVector(dx: 0, dy: 8), tune: tune)
    let down = flick(CGVector(dx: 0, dy: -8), tune: tune)
    assert(abs(up) > 3, "a vertical flick must visibly swing the pointer, got \(up)")
    assert(up * down < 0, "up and down must swing opposite ways")
    assert(abs(up) < abs(right), "vertical swing is the weaker of the two")

    // Any shape swings, as long as its mass is not on the pivot.
    let handish = CGVector(dx: 0.05, dy: -0.99)
    assert(abs(flick(CGVector(dx: 8, dy: 0), tune: tune, mass: handish)) > 5,
           "a hand-shaped cursor must swing too")

    // Inverting mirrors every direction.
    var inverted = tune
    inverted.direction = -1
    assert(flick(CGVector(dx: 8, dy: 0), tune: inverted) < 0, "invert must flip the swing")

    // Max tilt is a hard ceiling, whatever the sensitivity.
    var hot = tune
    hot.gain = 80
    assert(abs(flick(CGVector(dx: 60, dy: 0), tune: hot)) <= tune.maxAngleDeg + 1,
           "the tilt must never exceed the max angle")

    // Stopping dead — as at a screen edge — settles instead of spinning on.
    var p = SwingPhysics()
    for _ in 0..<18 {
        p.track(delta: CGVector(dx: 8, dy: 0), dt: 1.0 / 120)
        p.advance(dt: 1.0 / 120, tune: tune, centreOfMass: arrowMass)
    }
    for _ in 0..<180 {
        p.track(delta: .zero, dt: 1.0 / 120)
        p.advance(dt: 1.0 / 120, tune: tune, centreOfMass: arrowMass)
    }
    assert(abs(p.angleDeg) < 1.0, "the pointer must settle within 1.5 s, at \(p.angleDeg)")

    // Sliders dent at their default, and only near it.
    assert(Pref.damping.snapped(Pref.damping.default + 0.005) == Pref.damping.default,
           "a near-default drag must snap")
    assert(Pref.damping.snapped(0.90) == 0.90, "a far drag must not snap")

    // The centroid is measured from the real artwork, not assumed.
    let measured = CursorShape.arrow
    assert(measured.image.size.width > 0, "the system arrow must be readable")
    assert(measured.centreOfMass.dx > 0.2 && measured.centreOfMass.dy < -0.7,
           "the arrow's mass must sit down and right of its tip, got "
           + "\(measured.centreOfMass)")
    let hand = CursorShape(NSCursor.pointingHand)
    assert(hand.centreOfMass.dy < 0, "the pointing hand must hang below its hot spot")

    // Toggling the swing off and on from inside the settings panel must not
    // hide the real cursor: the overlay is suspended and would draw nothing.
    let hider = CursorHider()
    hider.hide()
    assert(hider.isHiding, "swing on means the real cursor is hidden")
    hider.suspend(for: .settingsPanel)
    assert(!hider.isHiding, "the settings panel gives the real cursor back")
    hider.show()                                   // swing switched off
    assert(!hider.isHiding, "swing off means the real cursor is visible")
    hider.hide()                                   // swing switched back on
    assert(!hider.isHiding, "the panel is still open — keep the real cursor")
    hider.resume(for: .settingsPanel)              // panel closed
    assert(hider.isHiding, "closing the panel hands the pointer back to the overlay")
    hider.show()

    // The panel is sized to its own fitting size, so it has to build and measure.
    let panel = NSHostingView(rootView: SettingsView(model: AppModel())).fittingSize
    assert(panel.width == 320 && panel.height > 300, "the panel must lay out, got \(panel)")

    print("self-test OK  (arrow mass \(measured.centreOfMass), hand mass \(hand.centreOfMass))")
}
