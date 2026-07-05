import AppKit
import QuartzCore
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    private let model: LaunchModel
    private var panel: OverlayPanel?
    private var localMonitor: Any?
    private var wheelAccumulation: CGFloat = 0
    private var lastWheelPageFlip = Date.distantPast
    private var horizontalSwipe = false
    private var dampedScrollDX: CGFloat = 0
    private var swipeEnergy: CGFloat = 0
    private var displayLink: CADisplayLink?

    var onOpenSettings: () -> Void = {}
    var onRescan: () -> Void = {}
    var onQuit: () -> Void = {}

    var isVisible: Bool { panel?.isVisible ?? false }

    init(model: LaunchModel) {
        self.model = model
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let screen = NSScreen.main else { return }

        model.reload()
        model.searchText = ""
        model.openFolderID = nil
        LauncherBus.shared.reset()

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        installLocalMonitor()
    }

    func hide() {
        guard let panel else { return }
        removeLocalMonitor()
        stopDisplayLink()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
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

        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = panel.contentView?.bounds ?? NSScreen.main?.frame ?? .zero
        effect.autoresizingMask = [.width, .height]

        let root = LauncherRootView(
            model: model,
            onDismiss: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.onOpenSettings()
            },
            onRescan: { [weak self] in self?.onRescan() },
            onQuit: { [weak self] in self?.onQuit() }
        )
        let host = NSHostingView(rootView: root)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)

        panel.contentView = effect
        return panel
    }

    private func installLocalMonitor() {
        removeLocalMonitor()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }

            if event.type == .scrollWheel {
                self.handleScroll(event)
                return event
            }

            if event.keyCode == 53 {
                if self.model.openFolderID != nil {
                    self.model.openFolderID = nil
                    return nil
                }
                self.hide()
                return nil
            }

            return event
        }
    }

    private func removeLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard model.openFolderID == nil, !model.settings.verticalScroll else { return }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let hasGesturePhase = !event.phase.isEmpty || !event.momentumPhase.isEmpty

        if hasGesturePhase {
            if event.phase.contains(.began) {
                horizontalSwipe = false
                dampedScrollDX = 0
                swipeEnergy = 0
            }
            if event.phase.contains(.changed) {
                if !horizontalSwipe && abs(dx) > abs(dy) {
                    horizontalSwipe = true
                    dampedScrollDX = 0
                    swipeEnergy = 0
                    startDisplayLink()
                }
                if horizontalSwipe {
                    if let dampedDX = dampedHorizontalDelta(dx) {
                        swipeEnergy += dampedDX
                        LauncherBus.shared.liveScroll(dx: dampedDX)
                    }
                }
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                if horizontalSwipe {
                    LauncherBus.shared.endScroll(velocity: dampedScrollDX, energy: swipeEnergy)
                }
                horizontalSwipe = false
                dampedScrollDX = 0
                swipeEnergy = 0
                stopDisplayLink()
            }
            return
        }

        guard abs(dx) > abs(dy) else {
            wheelAccumulation = 0
            return
        }

        wheelAccumulation += dx
        guard Date().timeIntervalSince(lastWheelPageFlip) > 0.3 else { return }

        if wheelAccumulation <= -40 {
            LauncherBus.shared.nextPage()
            wheelAccumulation = 0
            lastWheelPageFlip = Date()
        } else if wheelAccumulation >= 40 {
            LauncherBus.shared.previousPage()
            wheelAccumulation = 0
            lastWheelPageFlip = Date()
        }
    }

    private func dampedHorizontalDelta(_ dx: CGFloat) -> CGFloat? {
        let magnitude = abs(dx)
        guard magnitude >= 0.035 else { return nil }

        if dampedScrollDX != 0 && (dx > 0) != (dampedScrollDX > 0) {
            // Direction changes are usually intentional page resistance or a new gesture;
            // reset history so the filter does not pull against the finger.
            dampedScrollDX = 0
        }

        // Adaptive damping: slow micro-motion gets filtered, fast swipes stay responsive.
        let alpha = min(0.86, max(0.24, 0.22 + magnitude / 10.0))
        dampedScrollDX += (dx - dampedScrollDX) * alpha

        let directMix = min(0.45, max(0, (magnitude - 2.4) / 11.0))
        let output = dampedScrollDX * (1 - directMix) + dx * directMix

        return abs(output) >= 0.04 ? output : nil
    }

    private func startDisplayLink() {
        guard displayLink == nil, let panel else { return }
        // On macOS, CADisplayLink is created from NSWindow/NSView/NSScreen displayLink APIs.
        let link = panel.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let duration = link.targetTimestamp - link.timestamp
        LauncherBus.shared.displayFrame(duration: duration)
    }
}
