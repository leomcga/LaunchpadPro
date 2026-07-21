import CoreFoundation
import Foundation

// MultitouchSupport is a private macOS framework. Keeping its declarations and
// unsafe memory access in this file makes the compatibility boundary explicit.
private typealias MTDeviceRef = UnsafeMutableRawPointer
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

@_silgen_name("MTDeviceCreateDefault")
private func MTDeviceCreateDefault() -> MTDeviceRef?

@_silgen_name("MTDeviceCreateList")
private func MTDeviceCreateList() -> CFArray?

@_silgen_name("MTDeviceStart")
private func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

@_silgen_name("MTRegisterContactFrameCallback")
private func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallback)

struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

/// Memory layout used by MultitouchSupport on current Intel and Apple Silicon Macs.
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

private let launchpadProContactCallback: MTContactCallback = {
    _, touches, count, timestamp, _ in
    guard let touches, count > 0 else {
        // Some devices finish a contact sequence with a zero-contact frame and
        // no touch buffer. Forward that boundary so the one-shot latch resets.
        FiveFingerPinchMonitor.shared.endContactSequence()
        return 0
    }
    FiveFingerPinchMonitor.shared.process(
        touches: touches,
        count: Int(count),
        timestamp: timestamp
    )

    // This callback must stay observational. Returning 1 is not a supported
    // suppression mechanism and can prevent later contact sequences on macOS 26.
    return 0
}

/// Observes raw trackpad contacts and recognizes a deliberate five-finger pinch.
///
/// The monitor is intentionally process-lifetime: MultitouchSupport dispatches on
/// its own thread, so keeping one stable callback owner avoids teardown races.
final class FiveFingerPinchMonitor: @unchecked Sendable {
    static let shared = FiveFingerPinchMonitor()

    private let lock = NSLock()
    private var devices: [MTDeviceRef] = []
    private var hasStarted = false
    private var isEnabled = false
    private var recognizer = FiveFingerPinchRecognizer()
    private var action: (() -> Void)?
    private let frameworkAvailable: Bool

    private init() {
        frameworkAvailable = MTDeviceCreateList().map { CFArrayGetCount($0) > 0 } ?? false
    }

    var isAvailable: Bool {
        frameworkAvailable
    }

    /// Begins listening once and then cheaply gates recognition with `enabled`.
    /// Keeping the registered callback alive when the setting is toggled avoids
    /// private-framework start/stop races.
    func configure(enabled: Bool, action: @escaping () -> Void) {
        SystemPinchGestureOverride.shared.configure(enabled: enabled)

        lock.lock()
        isEnabled = enabled
        self.action = action
        if !enabled {
            recognizer.reset()
        }
        let shouldStart = enabled && !hasStarted
        if shouldStart {
            hasStarted = true
        }
        lock.unlock()

        if shouldStart {
            startDevices()
        }
    }

    fileprivate func endContactSequence() {
        lock.lock()
        if isEnabled {
            recognizer.reset()
        }
        lock.unlock()
    }

    private func startDevices() {
        var discovered: [MTDeviceRef] = []

        if let list = MTDeviceCreateList() {
            for index in 0..<CFArrayGetCount(list) {
                guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
                let device = UnsafeMutableRawPointer(mutating: value)
                if !discovered.contains(where: { $0 == device }) {
                    discovered.append(device)
                }
            }
        }

        if let fallback = MTDeviceCreateDefault(),
           !discovered.contains(where: { $0 == fallback }) {
            discovered.append(fallback)
        }

        guard !discovered.isEmpty else {
            lock.lock()
            hasStarted = false
            lock.unlock()
            return
        }

        for device in discovered {
            MTRegisterContactFrameCallback(device, launchpadProContactCallback)
            MTDeviceStart(device, 0)
        }

        lock.lock()
        devices = discovered
        lock.unlock()
    }

    fileprivate func process(
        touches: UnsafeMutableRawPointer,
        count: Int,
        timestamp: Double
    ) {
        lock.lock()
        guard isEnabled else {
            lock.unlock()
            return
        }

        let rawTouches = touches.bindMemory(to: MTTouch.self, capacity: count)
        var activePoints: [MTPoint] = []
        activePoints.reserveCapacity(count)

        for index in 0..<count {
            let touch = rawTouches[index]
            // States 3 and 4 are the stable contact states. Lift/linger frames are
            // ignored so a release cannot accidentally complete the pinch.
            guard touch.state == 3 || touch.state == 4 else { continue }
            activePoints.append(touch.normalizedVector.position)
        }

        let didRecognize = recognizer.process(points: activePoints, timestamp: timestamp)
        let action = didRecognize ? self.action : nil
        lock.unlock()

        if let action {
            DispatchQueue.main.async(execute: action)
        }
    }
}

/// macOS 26 maps the former Launchpad gesture to Spotlight Apps. Raw
/// MultitouchSupport callbacks are observable but do not reliably prevent that
/// system action, so suppress the system response while LaunchpadPro owns the
/// gesture.
///
/// On macOS 26 the Dock decides whether a pinch opens Spotlight Apps solely from
/// `com.apple.dock showLaunchpadGestureEnabled`. The AppleMultitouchTrackpad
/// `Trackpad*PinchGesture` keys gate recognition of the whole pinch/spread
/// family — System Settings writes them in pairs for the "Show Desktop" spread —
/// so zeroing them (as pre-1.2.1 builds did) breaks spread-to-show-desktop
/// without stopping the pinch. Only the Dock key is overridden now; the trackpad
/// keys are left untouched and restored if an older build zeroed them.
private final class SystemPinchGestureOverride: @unchecked Sendable {
    static let shared = SystemPinchGestureOverride()

    private struct Preference {
        let domain: String
        let key: String
        let defaultValue: Int

        var storageKey: String { "\(domain)|\(key)" }
    }

    private let dockPreference = Preference(
        domain: "com.apple.dock",
        key: "showLaunchpadGestureEnabled",
        defaultValue: 1
    )

    /// Keys suppressed by pre-1.2.1 builds. Never written to 0 anymore, only
    /// restored so upgraded installs get spread-to-show-desktop back.
    private let legacyPreferences = [
        Preference(
            domain: "com.apple.AppleMultitouchTrackpad",
            key: "TrackpadFourFingerPinchGesture",
            defaultValue: 2
        ),
        Preference(
            domain: "com.apple.AppleMultitouchTrackpad",
            key: "TrackpadFiveFingerPinchGesture",
            defaultValue: 2
        ),
        Preference(
            domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad",
            key: "TrackpadFourFingerPinchGesture",
            defaultValue: 2
        ),
        Preference(
            domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad",
            key: "TrackpadFiveFingerPinchGesture",
            defaultValue: 2
        )
    ]
    private let defaults = UserDefaults.standard
    private let activeKey = "codex.systemPinchOverrideActive"
    private let originalsKey = "codex.systemPinchOriginalValues"

    private init() {}

    func configure(enabled: Bool) {
        if enabled {
            enableOverride()
        } else {
            restoreOriginals()
        }
    }

    private func enableOverride() {
        var originals = defaults.dictionary(forKey: originalsKey) as? [String: Int] ?? [:]
        var didChange = restoreLegacyPreferences(originals: &originals)

        if !defaults.bool(forKey: activeKey) || originals[dockPreference.storageKey] == nil {
            originals[dockPreference.storageKey] =
                value(for: dockPreference) ?? dockPreference.defaultValue
        }
        defaults.set(originals, forKey: originalsKey)
        defaults.set(true, forKey: activeKey)

        if value(for: dockPreference) != 0 {
            setValue(0, for: dockPreference)
            didChange = true
        }
        synchronizeDomains()

        if didChange {
            restartDock()
        }
    }

    private func restoreOriginals() {
        guard defaults.bool(forKey: activeKey) else { return }
        var originals = defaults.dictionary(forKey: originalsKey) as? [String: Int] ?? [:]
        var didChange = restoreLegacyPreferences(originals: &originals)

        let original = originals[dockPreference.storageKey] ?? dockPreference.defaultValue
        if value(for: dockPreference) != original {
            setValue(original, for: dockPreference)
            didChange = true
        }
        synchronizeDomains()
        defaults.removeObject(forKey: originalsKey)
        defaults.set(false, forKey: activeKey)

        if didChange {
            restartDock()
        }
    }

    /// Undoes the pre-1.2.1 zeroing of the trackpad pinch/spread keys. A key is
    /// only touched while it reads 0, so user changes made after the upgrade win.
    private func restoreLegacyPreferences(originals: inout [String: Int]) -> Bool {
        var didChange = false
        for preference in legacyPreferences {
            defer { originals.removeValue(forKey: preference.storageKey) }
            guard value(for: preference) == 0 else { continue }
            let original = originals[preference.storageKey] ?? preference.defaultValue
            if original != 0 {
                setValue(original, for: preference)
                didChange = true
            }
        }
        return didChange
    }

    private func value(for preference: Preference) -> Int? {
        let value = CFPreferencesCopyAppValue(
            preference.key as CFString,
            preference.domain as CFString
        )
        return (value as? NSNumber)?.intValue
    }

    private func setValue(_ value: Int, for preference: Preference) {
        CFPreferencesSetAppValue(
            preference.key as CFString,
            NSNumber(value: value),
            preference.domain as CFString
        )
    }

    private func synchronizeDomains() {
        for domain in Set(legacyPreferences.map(\.domain) + [dockPreference.domain]) {
            CFPreferencesAppSynchronize(domain as CFString)
        }
    }

    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}

/// Geometry-only recognizer. It distinguishes a pinch from a five-finger swipe by
/// requiring the touch cloud to contract substantially while its centroid stays put.
struct FiveFingerPinchRecognizer {
    private static let minimumFingerCount = 5
    private static let minimumStartingSpread: Float = 0.09
    private static let minimumContraction: Float = 0.015
    private static let triggerRatio: Float = 0.90
    private static let maximumCentroidDrift: Float = 0.16
    private static let maximumGestureDuration = 2.0
    private static let newSequenceInterval = 0.30

    private var startingTimestamp: Double?
    private var lastFrameTimestamp: Double?
    private var startingCentroid: MTPoint?
    private var maximumSpread: Float = 0
    private var stablePinchFrames = 0
    private var missingFingerFrames = 0
    private var didTrigger = false

    mutating func process(points: [MTPoint], timestamp: Double) -> Bool {
        if let lastFrameTimestamp,
           timestamp - lastFrameTimestamp > Self.newSequenceInterval {
            reset()
        }
        lastFrameTimestamp = timestamp

        if didTrigger {
            if points.count <= 2 {
                reset()
            }
            return false
        }

        guard points.count >= Self.minimumFingerCount else {
            if startingTimestamp != nil {
                missingFingerFrames += 1
                if missingFingerFrames >= 3 {
                    reset()
                }
            }
            return false
        }

        missingFingerFrames = 0
        let centroid = Self.centroid(of: points)
        let spread = Self.averageSpread(of: points, around: centroid)

        guard let startedAt = startingTimestamp,
              let initialCentroid = startingCentroid else {
            startingTimestamp = timestamp
            startingCentroid = centroid
            maximumSpread = spread
            return false
        }

        if timestamp - startedAt > Self.maximumGestureDuration {
            reset()
            startingTimestamp = timestamp
            startingCentroid = centroid
            maximumSpread = spread
            return false
        }

        maximumSpread = max(maximumSpread, spread)
        let contraction = maximumSpread - spread
        let ratio = maximumSpread > 0 ? spread / maximumSpread : 1
        let centroidDrift = Self.distance(centroid, initialCentroid)

        if maximumSpread >= Self.minimumStartingSpread,
           contraction >= Self.minimumContraction,
           ratio <= Self.triggerRatio,
           centroidDrift <= Self.maximumCentroidDrift {
            stablePinchFrames += 1
        } else {
            stablePinchFrames = 0
        }

        guard stablePinchFrames >= 2 else { return false }
        didTrigger = true
        return true
    }

    mutating func reset() {
        startingTimestamp = nil
        lastFrameTimestamp = nil
        startingCentroid = nil
        maximumSpread = 0
        stablePinchFrames = 0
        missingFingerFrames = 0
        didTrigger = false
    }

    private static func centroid(of points: [MTPoint]) -> MTPoint {
        let sums = points.reduce(into: (x: Float(0), y: Float(0))) {
            $0.x += $1.x
            $0.y += $1.y
        }
        let count = Float(points.count)
        return MTPoint(x: sums.x / count, y: sums.y / count)
    }

    private static func averageSpread(of points: [MTPoint], around centroid: MTPoint) -> Float {
        let total = points.reduce(Float(0)) { result, point in
            result + distance(point, centroid)
        }
        return total / Float(points.count)
    }

    private static func distance(_ lhs: MTPoint, _ rhs: MTPoint) -> Float {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }
}
