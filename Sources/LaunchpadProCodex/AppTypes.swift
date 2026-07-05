import AppKit

struct AppRecord: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let originalName: String
    let path: String
    var bundleIdentifier: String?
    var dateAdded: Double

    var url: URL { URL(fileURLWithPath: path) }
}

struct FolderRecord: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var appIDs: [String]

    init(id: String = UUID().uuidString, name: String = "未命名", appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

enum LaunchEntry: Identifiable, Hashable {
    case app(String)
    case folder(FolderRecord)

    var id: String {
        switch self {
        case .app(let appID):
            return "app:" + appID
        case .folder(let folder):
            return "folder:" + folder.id
        }
    }

    var appID: String? {
        if case .app(let appID) = self { return appID }
        return nil
    }

    var folder: FolderRecord? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

struct SavedLayout: Codable {
    struct Slot: Codable, Hashable {
        var kind: String
        var appID: String?
        var folder: FolderRecord?
    }

    var slots: [Slot]
    var customNames: [String: String]
    var hiddenApps: [String]
    var pageIDs: [[String]]
    var layoutMemories: [LayoutMemory]?
}

struct LayoutMemory: Codable, Identifiable, Hashable {
    var slot: Int
    var savedAt: Double
    var slots: [SavedLayout.Slot]
    var customNames: [String: String]
    var hiddenApps: [String]
    var pageIDs: [[String]]

    var id: Int { slot }
}
