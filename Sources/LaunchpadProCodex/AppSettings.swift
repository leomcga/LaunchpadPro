import Combine
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let prefix = "codex."

    @Published var columns: Int { didSet { set(columns, "columns") } }
    @Published var rows: Int { didSet { set(rows, "rows") } }
    @Published var iconSize: Double { didSet { set(iconSize, "iconSize") } }
    @Published var showLabels: Bool { didSet { set(showLabels, "showLabels") } }
    @Published var verticalScroll: Bool { didSet { set(verticalScroll, "verticalScroll") } }
    @Published var sortMode: Int { didSet { set(sortMode, "sortMode") } }
    @Published var backgroundDim: Double { didSet { set(backgroundDim, "backgroundDim") } }
    @Published var hotCornersEnabled: Bool { didSet { set(hotCornersEnabled, "hotCornersEnabled") } }
    @Published var hotCorner: Int { didSet { set(hotCorner, "hotCorner") } }
    @Published var hotKey: Int {
        didSet {
            set(hotKey, "hotKey")
            onHotKeyChanged?()
        }
    }
    @Published var launchAtLogin: Bool { didSet { set(launchAtLogin, "launchAtLogin") } }
    @Published var showMenuBarIcon: Bool {
        didSet {
            set(showMenuBarIcon, "showMenuBarIcon")
            onMenuBarIconChanged?()
        }
    }

    var onHotKeyChanged: (() -> Void)?
    var onMenuBarIconChanged: (() -> Void)?

    private init() {
        columns = Self.readInt(defaults, prefix: prefix, key: "columns", defaultValue: 10)
        rows = Self.readInt(defaults, prefix: prefix, key: "rows", defaultValue: 5)
        iconSize = Self.readDouble(defaults, prefix: prefix, key: "iconSize", defaultValue: 76)
        showLabels = Self.readBool(defaults, prefix: prefix, key: "showLabels", defaultValue: true)
        verticalScroll = Self.readBool(defaults, prefix: prefix, key: "verticalScroll", defaultValue: false)
        sortMode = Self.readInt(defaults, prefix: prefix, key: "sortMode", defaultValue: 0)
        backgroundDim = Self.readDouble(defaults, prefix: prefix, key: "backgroundDim", defaultValue: 0.30)
        hotCornersEnabled = Self.readBool(defaults, prefix: prefix, key: "hotCornersEnabled", defaultValue: false)
        hotCorner = Self.readInt(defaults, prefix: prefix, key: "hotCorner", defaultValue: 3)
        hotKey = Self.readInt(defaults, prefix: prefix, key: "hotKey", defaultValue: 0)
        launchAtLogin = Self.readBool(defaults, prefix: prefix, key: "launchAtLogin", defaultValue: true)
        showMenuBarIcon = Self.readBool(defaults, prefix: prefix, key: "showMenuBarIcon", defaultValue: true)
    }

    private func key(_ name: String) -> String { prefix + name }
    private func set(_ value: Int, _ name: String) { defaults.set(value, forKey: key(name)) }
    private func set(_ value: Double, _ name: String) { defaults.set(value, forKey: key(name)) }
    private func set(_ value: Bool, _ name: String) { defaults.set(value, forKey: key(name)) }

    private static func readInt(_ defaults: UserDefaults, prefix: String, key: String, defaultValue: Int) -> Int {
        let fullKey = prefix + key
        return defaults.object(forKey: fullKey) == nil ? defaultValue : defaults.integer(forKey: fullKey)
    }

    private static func readDouble(_ defaults: UserDefaults, prefix: String, key: String, defaultValue: Double) -> Double {
        let fullKey = prefix + key
        return defaults.object(forKey: fullKey) == nil ? defaultValue : defaults.double(forKey: fullKey)
    }

    private static func readBool(_ defaults: UserDefaults, prefix: String, key: String, defaultValue: Bool) -> Bool {
        let fullKey = prefix + key
        return defaults.object(forKey: fullKey) == nil ? defaultValue : defaults.bool(forKey: fullKey)
    }
}

enum HotKeyPreset: Int, CaseIterable, Identifiable {
    case optionSpace = 0
    case controlSpace = 1
    case commandOptionSpace = 2
    case f4 = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlSpace: return "⌃ Space"
        case .commandOptionSpace: return "⌘⌥ Space"
        case .f4: return "F4"
        }
    }
}
