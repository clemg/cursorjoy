import AppKit
import ServiceManagement
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = SwingOverlay()
    private let model = AppModel()
    private lazy var settings = SettingsPanel(overlay: overlay, model: model)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        wireModel()
        makeStatusItem()

        if !Pref.hasAskedLaunchAtLogin { askAboutLaunchAtLogin() }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.swingEnabled = true
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.disable()
    }

    /// Reopening from Applications/Spotlight brings a hidden menu bar icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if statusItem == nil { makeStatusItem() }
        openSettings()
        return true
    }

    private func wireModel() {
        model.onSwingChange = { [weak self] on in
            guard let self else { return }
            on ? self.overlay.enable() : self.overlay.disable()
            self.refreshStatusItem()
        }
        model.onLaunchChange = { [weak self] on in
            self?.setLaunchAtLogin(on)
        }
    }

    private func makeStatusItem() {
        removeStatusItem()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        let on = overlay.isEnabled
        let symbol = on ? "cursorarrow.motionlines" : "cursorarrow"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol,
                                            accessibilityDescription: "Cursor Joy")
        statusItem?.button?.toolTip = on ? "Swing is on" : "Swing is off"
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            settings.toggle(below: statusItemFrame)
        }
    }

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private var statusItemFrame: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// The panel is the place for settings; the menu is just the escape hatch.
    private func showMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let entries = [
            NSMenuItem(title: "Hide Menu Bar Icon",
                       action: #selector(hideStatusItem), keyEquivalent: ""),
            NSMenuItem.separator(),
            NSMenuItem(title: "Quit Cursor Joy",
                       action: #selector(quit), keyEquivalent: "q"),
        ]
        for entry in entries {
            entry.target = self
            menu.addItem(entry)
        }

        // Attaching only for this click keeps left-click free for the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func openSettings() { settings.show(below: statusItemFrame) }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func hideStatusItem() {
        removeStatusItem()

        let alert = NSAlert()
        alert.messageText = "Cursor Joy is hidden from the menu bar"
        alert.informativeText = "It keeps running. Open Cursor Joy again from Applications "
            + "or Spotlight to bring the icon back."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func askAboutLaunchAtLogin() {
        Pref.hasAskedLaunchAtLogin = true
        let alert = NSAlert()
        alert.messageText = "Welcome to Cursor Joy"
        alert.informativeText = "Launch Cursor Joy automatically when you log in?"
        alert.addButton(withTitle: "Launch at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { setLaunchAtLogin(true) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled: try SMAppService.mainApp.register()
            case (false, .enabled): try SMAppService.mainApp.unregister()
            default: break
            }
        } catch {
            os_log("Could not change the login item: %{public}@",
                   log: cursorJoyLog, type: .error, error.localizedDescription)
        }
    }
}
