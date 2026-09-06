import AppKit

// NSApplication has to exist before NSCursor will hand out real artwork.
let app = NSApplication.shared

if ProcessInfo.processInfo.environment["CURSORJOY_SELFTEST"] == "1" {
    runSelfTest()
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
