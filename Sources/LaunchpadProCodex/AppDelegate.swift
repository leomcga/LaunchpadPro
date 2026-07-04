import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = LaunchModel()
    private let settings = AppSettings.shared
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var globalMouseMonitor: Any?
    private var lastCornerHit = Date.distantPast
    private var pendingShowOnLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayController(model: model)
        overlay.onOpenSettings = { [weak self] in self?.openSettings() }
        overlay.onRescan = { [weak self] in self?.rescan() }
        overlay.onQuit = { NSApp.terminate(nil) }

        setupStatusItem()
        setupHotKey()
        setupHotCorners()
        applyLaunchAtLogin()

        settings.onHotKeyChanged = { [weak self] in self?.setupHotKey() }

        if pendingShowOnLaunch {
            pendingShowOnLaunch = false
            DispatchQueue.main.async { [weak self] in self?.overlay.show() }
        }

        if ProcessInfo.processInfo.environment["LAUNCHPADPRO_CODEX_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.overlay.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.show()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard overlay != nil else {
            pendingShowOnLaunch = true
            return
        }

        for url in urls where url.scheme == "launchpadprocodex" {
            switch url.host?.lowercased() {
            case "toggle":
                overlay.toggle()
            case "settings":
                openSettings()
            default:
                overlay.show()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = AppBranding.menuBarIcon()
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            overlay.toggle()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开启动器", action: #selector(openLauncher), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "重新扫描 App", action: #selector(rescan), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 LaunchpadPro Codex", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func openLauncher() {
        overlay.show()
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                model: model,
                onHotCornersChanged: { [weak self] in self?.setupHotCorners() },
                onLaunchAtLoginChanged: { [weak self] in self?.applyLaunchAtLogin() }
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func rescan() {
        model.reload()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupHotKey() {
        let combo = hotKeyCombo(HotKeyPreset(rawValue: settings.hotKey) ?? .optionSpace)
        HotKeyManager.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers) { [weak self] in
            self?.overlay.toggle()
        }
    }

    private func hotKeyCombo(_ preset: HotKeyPreset) -> (keyCode: UInt32, modifiers: UInt32) {
        switch preset {
        case .optionSpace:
            return (UInt32(kVK_Space), UInt32(optionKey))
        case .controlSpace:
            return (UInt32(kVK_Space), UInt32(controlKey))
        case .commandOptionSpace:
            return (UInt32(kVK_Space), UInt32(cmdKey | optionKey))
        case .f4:
            return (UInt32(kVK_F4), 0)
        }
    }

    private func setupHotCorners() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        guard settings.hotCornersEnabled else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.checkHotCorner() }
        }
    }

    private func checkHotCorner() {
        guard let screen = NSScreen.main else { return }

        let frame = screen.frame
        let location = NSEvent.mouseLocation
        let margin: CGFloat = 3

        let hit: Bool
        switch settings.hotCorner {
        case 0:
            hit = location.x <= frame.minX + margin && location.y >= frame.maxY - margin
        case 1:
            hit = location.x >= frame.maxX - margin && location.y >= frame.maxY - margin
        case 2:
            hit = location.x <= frame.minX + margin && location.y <= frame.minY + margin
        default:
            hit = location.x >= frame.maxX - margin && location.y <= frame.minY + margin
        }

        guard hit, Date().timeIntervalSince(lastCornerHit) > 1.2 else { return }
        lastCornerHit = Date()
        if !overlay.isVisible {
            overlay.show()
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Development/ad-hoc builds can fail registration; manual launch still works.
        }
    }
}
