import SwiftUI
import Combine

/// Single source of truth for all user-tunable settings, backed by UserDefaults.
/// Both the launcher overlay and the Settings window observe this object so
/// changes apply live.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    @Published var columns: Int          { didSet { d.set(columns, forKey: "columns") } }
    @Published var rows: Int             { didSet { d.set(rows, forKey: "rows") } }
    @Published var iconSize: Double      { didSet { d.set(iconSize, forKey: "iconSize") } }
    @Published var verticalScroll: Bool  { didSet { d.set(verticalScroll, forKey: "verticalScroll") } }
    @Published var sortMode: Int         { didSet { d.set(sortMode, forKey: "sortMode") } }  // 0 custom 1 name 2 dateAdded
    @Published var showLabels: Bool      { didSet { d.set(showLabels, forKey: "showLabels") } }
    @Published var backgroundDim: Double { didSet { d.set(backgroundDim, forKey: "backgroundDim") } }
    @Published var hotCornersEnabled: Bool { didSet { d.set(hotCornersEnabled, forKey: "hotCornersEnabled") } }
    @Published var hotCorner: Int        { didSet { d.set(hotCorner, forKey: "hotCorner") } }
    @Published var hotKey: Int           { didSet { d.set(hotKey, forKey: "hotKey"); onHotKeyChange?() } }
    @Published var launchAtLogin: Bool   { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }

    /// Called when the activation hotkey preset changes so the delegate can
    /// re-register it.
    var onHotKeyChange: (() -> Void)?

    private init() {
        let ud = UserDefaults.standard
        func int(_ k: String, _ def: Int) -> Int { ud.object(forKey: k) == nil ? def : ud.integer(forKey: k) }
        func dbl(_ k: String, _ def: Double) -> Double { ud.object(forKey: k) == nil ? def : ud.double(forKey: k) }
        func bool(_ k: String, _ def: Bool) -> Bool { ud.object(forKey: k) == nil ? def : ud.bool(forKey: k) }

        columns = int("columns", 10)
        rows = int("rows", 5)
        iconSize = dbl("iconSize", 72)
        verticalScroll = bool("verticalScroll", false)
        sortMode = int("sortMode", 0)
        showLabels = bool("showLabels", true)
        backgroundDim = dbl("backgroundDim", 0.28)
        hotCornersEnabled = bool("hotCornersEnabled", false)
        hotCorner = int("hotCorner", 3)
        hotKey = int("hotKey", 0)        // 0 = ⌥Space
        launchAtLogin = bool("launchAtLogin", true)
    }
}

/// Selectable activation hotkey presets.
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
