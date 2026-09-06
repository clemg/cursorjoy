import AppKit
import QuartzCore
import os.lock

/// Per-frame callback that actually keeps up with the display.
///
/// A `CADisplayLink` added to the *main* run loop is delivered at 60 Hz under
/// `NSApp.run()` however fast the screen is: measured on a 165 Hz display the
/// link's own nominal frame was 6.06 ms (165 Hz) while callbacks arrived at
/// 60 Hz, even for a do-nothing handler. The real pointer runs at the panel
/// rate, so a 60 Hz pointer visibly trails it.
///
/// Driving the link from its own run loop and hopping each frame back to main
/// delivers all of them. The body still runs on the main thread, so nothing it
/// touches has to be thread-safe.
final class FrameDriver {
    private var link: CADisplayLink?
    private var thread: Thread?
    private let pending = OSAllocatedUnfairLock(initialState: false)
    private var lastFrame = CACurrentMediaTime()
    private var body: ((CFTimeInterval, CFTimeInterval) -> Void)?

    /// `body` receives the current time and the seconds since the last frame,
    /// capped so a stall cannot hand the physics a huge step.
    func start(in window: NSWindow, _ body: @escaping (CFTimeInterval, CFTimeInterval) -> Void) {
        stop()
        self.body = body
        lastFrame = CACurrentMediaTime()

        let link = window.displayLink(target: self, selector: #selector(fired))
        self.link = link

        let thread = Thread {
            link.add(to: RunLoop.current, forMode: .default)
            while !Thread.current.isCancelled {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1))
            }
        }
        thread.name = "CursorJoy.displayLink"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        link?.invalidate()
        link = nil
        thread?.cancel()
        thread = nil
        body = nil
    }

    /// Runs on the display-link thread. Drops a frame rather than queueing when
    /// the main thread has not finished the previous one.
    @objc private func fired() {
        let busy = pending.withLock { pending -> Bool in
            if pending { return true }
            pending = true
            return false
        }
        guard !busy else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending.withLock { $0 = false }
            let now = CACurrentMediaTime()
            let dt = (now - lastFrame).clamped(to: 0...0.05)
            lastFrame = now
            body?(now, dt)
        }
    }
}
