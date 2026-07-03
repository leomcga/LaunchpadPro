import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = LaunchModel()
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var globalMouseMonitor: Any?
    private var lastCornerTrigger: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon

        overlay = OverlayController(model: model)
        setupStatusItem()
        setupHotKey()
        setupHotCorners()

        // Hidden smoke-test hook: LAUNCHPADPRO_AUTOSHOW=1 opens the overlay so
        // the render path can be exercised without a hotkey.
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
        menu.addItem(.separator())

        let vScroll = NSMenuItem(title: "竖向滚动视图", action: #selector(toggleVerticalScroll), keyEquivalent: "")
        vScroll.state = model.verticalScroll ? .on : .off
        menu.addItem(vScroll)

        let corners = NSMenuItem(title: "触发角唤起", action: #selector(toggleHotCorners), keyEquivalent: "")
        corners.state = model.hotCornersEnabled ? .on : .off
        menu.addItem(corners)

        menu.addItem(withTitle: "重新扫描 App", action: #selector(rescan), keyEquivalent: "r")
        menu.addItem(withTitle: "显示所有隐藏的 App", action: #selector(unhideAll), keyEquivalent: "")
        menu.addItem(.separator())

        let colMenu = NSMenu()
        for c in [5, 6, 7, 8, 9] {
            let it = NSMenuItem(title: "\(c) 列", action: #selector(setColumns(_:)), keyEquivalent: "")
            it.tag = c
            it.state = model.columns == c ? .on : .off
            colMenu.addItem(it)
        }
        let colParent = NSMenuItem(title: "每行图标数", action: nil, keyEquivalent: "")
        menu.setSubmenu(colMenu, for: colParent)
        menu.addItem(colParent)

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 LaunchpadPro", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        // targets for submenu
        for item in colMenu.items { item.target = self }
        return menu
    }

    @objc private func openLauncher() { overlay.show() }
    @objc private func rescan() { model.reload() }
    @objc private func unhideAll() { model.unhideAll() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleVerticalScroll() { model.verticalScroll.toggle() }
    @objc private func toggleHotCorners() {
        model.hotCornersEnabled.toggle()
        setupHotCorners()
    }
    @objc private func setColumns(_ sender: NSMenuItem) { model.columns = sender.tag }

    // MARK: - Global hotkey (⌥Space)

    private func setupHotKey() {
        HotKeyManager.shared.register(keyCode: HotKeyDefaults.optionSpace.keyCode,
                                      modifiers: HotKeyDefaults.optionSpace.modifiers) { [weak self] in
            self?.overlay.toggle()
        }
    }

    // MARK: - Hot corners (Pro)

    private func setupHotCorners() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        guard model.hotCornersEnabled else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.checkHotCorner()
        }
    }

    private func checkHotCorner() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let loc = NSEvent.mouseLocation
        let margin: CGFloat = 3
        let corner = model.hotCorner
        var hit = false
        switch corner {
        case 0: hit = loc.x <= frame.minX + margin && loc.y >= frame.maxY - margin   // top-left
        case 1: hit = loc.x >= frame.maxX - margin && loc.y >= frame.maxY - margin   // top-right
        case 2: hit = loc.x <= frame.minX + margin && loc.y <= frame.minY + margin   // bottom-left
        default: hit = loc.x >= frame.maxX - margin && loc.y <= frame.minY + margin  // bottom-right
        }
        if hit {
            if Date().timeIntervalSince(lastCornerTrigger) > 1.2 {
                lastCornerTrigger = Date()
                if !overlay.isVisible { overlay.show() }
            }
        }
    }
}
