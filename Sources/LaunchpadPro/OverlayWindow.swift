import AppKit
import SwiftUI

/// Borderless full-screen panel that hosts the launcher grid. Behaves like the
/// classic Launchpad overlay: appears above everything, dismisses on Esc, on
/// launching an app, or when it loses focus.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private let model: LaunchModel
    private var localMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(model: LaunchModel) {
        self.model = model
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        model.searchText = ""
        model.openFolderID = nil

        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }

        installLocalMonitor()
    }

    func hide() {
        guard let panel = panel else { return }
        removeLocalMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .init(Int(CGWindowLevelForKey(.maximumWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        // A single window-level frost so all pages slide over one continuous
        // blurred layer (no seam between pages during transitions).
        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = panel.contentView?.bounds ?? .zero
        effect.autoresizingMask = [.width, .height]

        let root = LauncherRootView(model: model, onDismiss: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        // Keep the hosting view transparent so the frost shows through.
        hosting.layer?.backgroundColor = .clear

        effect.addSubview(hosting)
        panel.contentView = effect
        return panel
    }

    // Dismiss when the user presses Esc, or clicks outside handled inside SwiftUI.
    private func installLocalMonitor() {
        removeLocalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                if self?.model.openFolderID != nil {
                    self?.model.openFolderID = nil
                    return nil
                }
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeLocalMonitor() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
