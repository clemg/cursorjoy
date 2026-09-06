import CoreGraphics
import Foundation

/// The pointer modelled as a pendulum hanging from its hot spot.
///
/// Drag opposes the pointer's motion and pulls on the artwork's centre of mass,
/// which for an arrow sits down and to the right of the tip. Because that offset
/// is not straight down, a vertical flick torques it just like a horizontal one —
/// weaker, in the ratio of the centre of mass' x to its y. Every cursor shape
/// gets the same treatment, so a pointing hand swings like the arrow does.
struct SwingPhysics {
    /// Degrees, positive = clockwise on screen.
    private(set) var angleDeg = 0.0
    private(set) var angularVel = 0.0
    /// Smoothed pointer velocity in points per millisecond.
    private(set) var velocity = CGVector.zero

    private static let velocitySmoothingMs = 35.0
    /// Anything below this is hand tremor, not a flick.
    private static let restVelocity = 0.002

    mutating func reset() { self = SwingPhysics() }

    /// Feed the pointer's movement since the last frame.
    mutating func track(delta: CGVector, dt: TimeInterval) {
        let ms = max(dt * 1000, 0.5)
        let instant = CGVector(dx: delta.dx / ms, dy: delta.dy / ms)
        let alpha = 1 - exp(-min(ms, 60) / Self.velocitySmoothingMs)
        velocity.dx += (instant.dx - velocity.dx) * alpha
        velocity.dy += (instant.dy - velocity.dy) * alpha
    }

    /// Where the shape would hang if the current velocity held forever.
    func restingAngle(_ tune: SwingTune, centreOfMass com: CGVector) -> Double {
        // -(r x F).z for a drag force F = -velocity, as a clockwise-positive angle.
        let torque = com.dx * velocity.dy - com.dy * velocity.dx
        return (tune.direction * torque * tune.gain)
            .clamped(to: -tune.maxAngleDeg...tune.maxAngleDeg)
    }

    /// Damped spring toward `restingAngle`, sub-stepped so high wobble rates
    /// stay stable.
    mutating func advance(dt: TimeInterval, tune: SwingTune, centreOfMass: CGVector) {
        let target = restingAngle(tune, centreOfMass: centreOfMass)
        let w = 2 * .pi * tune.frequencyHz
        let stiffness = w * w
        let drag = 2 * tune.damping * w

        var remaining = min(dt, 0.05)
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240.0)
            angularVel += (stiffness * (target - angleDeg) - drag * angularVel) * step
            angleDeg += angularVel * step
            remaining -= step
        }
        if abs(angleDeg) < 0.01, abs(angularVel) < 0.05,
           hypot(velocity.dx, velocity.dy) < Self.restVelocity {
            angleDeg = 0
            angularVel = 0
        }
    }
}
