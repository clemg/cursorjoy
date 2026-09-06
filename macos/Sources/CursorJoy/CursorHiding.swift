import CoreGraphics
import Foundation
import os.log

let cursorJoyLog = OSLog(subsystem: "com.cursorjoy.swing", category: "CursorJoy")

/// Private CoreGraphics entry points, resolved at runtime
enum CGSPrivate {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty =
        @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private typealias CursorIsVisible = @convention(c) () -> Bool
    private typealias GetCursorScale = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32

    private static let handle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let connection = symbol("_CGSDefaultConnection", as: DefaultConnection.self)
    private static let setProperty = symbol("CGSSetConnectionProperty",
                                            as: SetConnectionProperty.self)
    private static let isVisible = symbol("CGCursorIsVisible", as: CursorIsVisible.self)
    private static let cursorScale = symbol("CGSGetCursorScale", as: GetCursorScale.self)

    /// Lets a background app's hide/show calls affect the whole system.
    static func allowBackgroundCursorControl() {
        guard let conn = connection?(), let setProperty else {
            os_log("Private CGS API unavailable: hiding will be unreliable",
                   log: cursorJoyLog, type: .error)
            return
        }
        let err = setProperty(conn, conn, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        if err != 0 {
            os_log("SetsCursorInBackground failed (%d)", log: cursorJoyLog, type: .error, err)
        }
    }

    static var cursorIsVisible: Bool { isVisible?() ?? true }

    static var systemCursorScale: Double {
        guard let conn = connection?(), let cursorScale else { return 1 }
        var scale: Float = 1
        return cursorScale(conn, &scale) == 0 ? Double(scale) : 1
    }
}

/// Keeps the real pointer hidden while we draw our own, and always unwinds its
/// hides so quitting (or any suspension) restores the cursor.
final class CursorHider {
    enum Reason: Hashable {
        case settingsPanel
        case unreadableCursor
    }

    private var wantsHidden = false
    private var hides = 0
    private var suspended: Set<Reason> = []

    init() { CGSPrivate.allowBackgroundCursorControl() }

    /// True when the real cursor should be hidden right now.
    var isHiding: Bool { wantsHidden && suspended.isEmpty }

    func hide() {
        wantsHidden = true
        reassert()
    }

    func show() {
        // Deliberately does NOT clear `suspended`: a reason like .settingsPanel
        // must outlive an off/on cycle of the swing, or re-enabling from inside
        // the panel hides the real cursor while the overlay is still suspended
        // and nothing draws a pointer at all. unwind() restores the cursor
        // unconditionally, so quitting is still safe.
        wantsHidden = false
        unwind()
    }

    /// Show the real pointer again for as long as `reason` holds.
    func suspend(for reason: Reason) {
        guard suspended.insert(reason).inserted else { return }
        unwind()
    }

    func resume(for reason: Reason) {
        guard suspended.remove(reason) != nil, suspended.isEmpty else { return }
        reassert()
    }

    /// Other apps push their own cursor state; re-hide whenever they do.
    func reassert() {
        guard wantsHidden, suspended.isEmpty, CGSPrivate.cursorIsVisible else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        hides += 1
    }

    private func unwind() {
        var safety = 512
        while hides > 0 && safety > 0 {
            CGDisplayShowCursor(CGMainDisplayID())
            hides -= 1
            safety -= 1
        }
        while !CGSPrivate.cursorIsVisible && safety > 0 {
            CGDisplayShowCursor(CGMainDisplayID())
            safety -= 1
        }
    }
}
