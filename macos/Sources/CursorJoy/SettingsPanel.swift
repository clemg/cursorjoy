import AppKit
import SwiftUI

/// A borderless panel still needs to take key so its sliders respond.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The settings UI, presented Control-Centre style: a translucent rounded panel
/// hanging under the menu bar icon that closes the moment you click away.
final class SettingsPanel: NSObject, NSWindowDelegate {
    private let overlay: SwingOverlay
    private let model: AppModel
    private var panel: KeyPanel?
    private var shownAt = Date.distantPast

    init(overlay: SwingOverlay, model: AppModel) {
        self.overlay = overlay
        self.model = model
    }

    var isOpen: Bool { panel != nil }

    func toggle(below anchor: NSRect?) {
        isOpen ? close() : show(below: anchor)
    }

    func show(below anchor: NSRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        overlay.suspend()
        position(panel, below: anchor)
        shownAt = Date()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closing throws the panel away rather than hiding it: that releases the
    /// preview's display link instead of leaving it ticking out of sight.
    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.close()
        overlay.resume()
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                             styleMask: .borderless, backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass tiles carry their own shading; a window shadow would draw a
        // rectangle behind their rounded corners.
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let content = NSHostingView(rootView: SettingsView(model: model))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        // SwiftUI's .glassEffect had no backdrop to sample inside a borderless
        // transparent panel: it fell back to a flat fill that ignored the corner
        // radius — which was both the "not Liquid Glass" and the "square corners"
        // bug. AppKit's glass view owns the shape where the compositor can see it.
        // It pins its contentView with Auto Layout and forwards fittingSize, so
        // position() still measures the panel correctly through it.
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 22
        glass.contentView = content
        panel.contentView = glass
        return panel
    }

    /// Hang under the status item, nudged back on screen if it would overflow.
    private func position(_ panel: NSPanel, below anchor: NSRect?) {
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor ?? .zero) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let anchorRect = anchor ?? NSRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
        var x = anchorRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(anchorRect.minY - 8, visible.maxY - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    // Clicking anywhere outside dismisses it, like Control Centre — but not in
    // the instant after opening, while the app is still coming forward.
    func windowDidResignKey(_ notification: Notification) {
        guard Date().timeIntervalSince(shownAt) > 0.3 else { return }
        close()
    }
}
