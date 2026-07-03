import AppKit

/// A single installed application discovered on disk.
struct AppItem: Identifiable, Codable, Hashable {
    let id: String            // stable id = bundle path
    var name: String          // display name (may be user-overridden)
    let originalName: String   // name as read from disk
    let path: String          // full path to the .app bundle
    var bundleID: String?
    var dateAdded: Double = 0 // file creation time (seconds since 1970)

    var url: URL { URL(fileURLWithPath: path) }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A folder that groups several apps together (classic Launchpad folder).
struct Folder: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var appIDs: [String]

    init(id: String = UUID().uuidString, name: String, appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

/// A top-level slot on the launcher grid: either an app or a folder.
enum LaunchEntry: Identifiable, Hashable {
    case app(String)          // app id
    case folder(Folder)

    var id: String {
        switch self {
        case .app(let appID): return "app:" + appID
        case .folder(let folder): return "folder:" + folder.id
        }
    }
}

/// Codable representation of the persisted layout.
struct SavedLayout: Codable {
    struct Slot: Codable {
        var kind: String          // "app" | "folder"
        var appID: String?
        var folder: Folder?
    }
    var slots: [Slot]
    var customNames: [String: String]   // appID -> custom name
    var hiddenApps: [String]
}
