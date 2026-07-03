import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = LaunchModel()
    let settings = AppSettings.shared
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var globalMouseMonitor: Any?
    private var lastCornerTrigger: Date = .distantPast
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon

        overlay = OverlayController(model: model)
        overlay.onOpenSettings = { [weak self] in self?.openSettings() }
        overlay.onRescan = { [weak self] in self?.rescan() }
        overlay.onQuit = { NSApp.terminate(nil) }
        setupStatusItem()
        setupHotKey()
        setupHotCorners()
        applyLaunchAtLogin()

        // Re-register the hotkey whenever the preset changes in Settings.
        settings.onHotKeyChange = { [weak self] in self?.setupHotKey() }

        if ProcessInfo.processInfo.environment["LAUNCHPADPRO_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.overlay.show()
            }
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "LaunchpadPro")
            button.action = #selector(statusClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            overlay.toggle()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开启动器", action: #selector(openLauncher), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "重新扫描 App", action: #selector(rescan), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 LaunchpadPro", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func openLauncher() { overlay.show() }
    @objc private func rescan() { model.reload() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model,
                                                          onHotCornersChanged: { [weak self] in self?.setupHotCorners() },
                                                          onLaunchAtLoginChanged: { [weak self] in self?.applyLaunchAtLogin() })
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Global hotkey (configurable preset)

    private func setupHotKey() {
        let (keyCode, mods) = hotKeyCombo(for: HotKeyPreset(rawValue: settings.hotKey) ?? .optionSpace)
        HotKeyManager.shared.register(keyCode: keyCode, modifiers: mods) { [weak self] in
            self?.overlay.toggle()
        }
    }

    private func hotKeyCombo(for preset: HotKeyPreset) -> (UInt32, UInt32) {
        switch preset {
        case .optionSpace:        return (UInt32(kVK_Space), UInt32(optionKey))
        case .controlSpace:       return (UInt32(kVK_Space), UInt32(controlKey))
        case .commandOptionSpace: return (UInt32(kVK_Space), UInt32(cmdKey | optionKey))
        case .f4:                 return (UInt32(kVK_F4), 0)
        }
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Registration can fail for unsigned/dev builds; the login-item that
            // was added manually still covers auto-start, so ignore.
        }
    }

    // MARK: - Hot corners

    private func setupHotCorners() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        guard settings.hotCornersEnabled else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.checkHotCorner()
        }
    }

    private func checkHotCorner() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let loc = NSEvent.mouseLocation
        let margin: CGFloat = 3
        var hit = false
        switch settings.hotCorner {
        case 0: hit = loc.x <= frame.minX + margin && loc.y >= frame.maxY - margin
        case 1: hit = loc.x >= frame.maxX - margin && loc.y >= frame.maxY - margin
        case 2: hit = loc.x <= frame.minX + margin && loc.y <= frame.minY + margin
        default: hit = loc.x >= frame.maxX - margin && loc.y <= frame.minY + margin
        }
        if hit, Date().timeIntervalSince(lastCornerTrigger) > 1.2 {
            lastCornerTrigger = Date()
            if !overlay.isVisible { overlay.show() }
        }
    }
}
