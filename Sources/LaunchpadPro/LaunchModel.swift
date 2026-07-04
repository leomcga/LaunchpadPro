import AppKit
import SwiftUI
import Combine

/// The central observable state for the launcher: app list, layout, folders,
/// search, and persistence.
@MainActor
final class LaunchModel: ObservableObject {

    @Published private(set) var apps: [AppItem] = []
    @Published var entries: [LaunchEntry] = []      // top-level ordered grid
    @Published var searchText: String = ""
    @Published var openFolderID: String? = nil       // folder currently expanded

    /// appID -> custom name override
    @Published private(set) var customNames: [String: String] = [:]
    /// hidden app ids (not shown on the grid)
    @Published private(set) var hiddenApps: Set<String> = []

    private var appIndex: [String: AppItem] = [:]

    /// Shared tunable settings (grid size, hotkey, corners, appearance).
    let settings = AppSettings.shared

    init() {
        reload()
    }

    // MARK: - Loading

    func reload() {
        let scanned = AppScanner.scan()
        apps = scanned
        appIndex = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
        load()
        rebuildEntriesFromLayout(scanned: scanned)
        applySort()
    }

    func app(for id: String) -> AppItem? { appIndex[id] }

    func displayName(for id: String) -> String {
        if let custom = customNames[id], !custom.isEmpty { return custom }
        return appIndex[id]?.name ?? id
    }

    // MARK: - Visible entries (respecting search + hidden)

    var visibleApps: [AppItem] {
        apps.filter { !hiddenApps.contains($0.id) }
    }

    /// Entries to render given the current search text.
    var displayEntries: [LaunchEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            // Filter out any entries that point at hidden/removed apps.
            return entries.compactMap { entry in
                switch entry {
                case .app(let id):
                    guard appIndex[id] != nil, !hiddenApps.contains(id) else { return nil }
                    return entry
                case .folder(var folder):
                    folder.appIDs = folder.appIDs.filter { appIndex[$0] != nil && !hiddenApps.contains($0) }
                    if folder.appIDs.isEmpty { return nil }
                    return .folder(folder)
                }
            }
        } else {
            // Flat search over all (non-hidden) apps by name.
            return visibleApps
                .filter { displayName(for: $0.id).lowercased().contains(query) }
                .map { .app($0.id) }
        }
    }

    func appsInFolder(_ folder: Folder) -> [AppItem] {
        folder.appIDs.compactMap { appIndex[$0] }
    }

    // MARK: - Launching

    func launch(_ id: String) {
        guard let item = appIndex[id] else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: cfg) { _, _ in }
    }

    // MARK: - Renaming / hiding / uninstalling

    func rename(_ id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == appIndex[id]?.originalName {
            customNames.removeValue(forKey: id)
        } else {
            customNames[id] = trimmed
        }
        save()
        objectWillChange.send()
    }

    func renameFolder(_ folderID: String, to newName: String) {
        for i in entries.indices {
            if case .folder(var f) = entries[i], f.id == folderID {
                f.name = newName
                entries[i] = .folder(f)
            }
        }
        save()
    }

    func hide(_ id: String) {
        hiddenApps.insert(id)
        // also drop from any folder
        removeAppFromFolders(id)
        save()
        objectWillChange.send()
    }

    /// Wipe folders, ordering, renames and hidden state back to defaults.
    func resetLayout() {
        customNames.removeAll()
        hiddenApps.removeAll()
        loadedLayout = nil
        entries = apps.map { .app($0.id) }
        applySort()
        save()
        objectWillChange.send()
    }

    func unhide(_ id: String) {
        hiddenApps.remove(id)
        if !entries.contains(where: { if case .app(let a) = $0 { return a == id } else { return false } }) {
            entries.append(.app(id))
        }
        save()
        objectWillChange.send()
    }

    func unhideAll() {
        hiddenApps.removeAll()
        rebuildEntriesFromLayout(scanned: apps)
        save()
    }

    func revealInFinder(_ id: String) {
        guard let item = appIndex[id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Move an app bundle to the Trash (full uninstall — Pro feature).
    func uninstall(_ id: String) {
        guard let item = appIndex[id] else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            hiddenApps.remove(id)
            removeAppFromFolders(id)
            entries.removeAll { if case .app(let a) = $0 { return a == id } else { return false } }
            apps.removeAll { $0.id == id }
            appIndex.removeValue(forKey: id)
            save()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Layout mutation (reorder + folders)

    func moveEntry(from source: Int, to destination: Int) {
        guard source != destination, entries.indices.contains(source) else { return }
        let item = entries.remove(at: source)
        let dest = destination > source ? destination - 1 : destination
        entries.insert(item, at: min(max(dest, 0), entries.count))
        save()
    }

    /// Drop app `draggedID` onto entry at `targetIndex` -> create/extend folder.
    func combine(draggedEntryID: String, ontoIndex targetIndex: Int) {
        guard let sourceIndex = entries.firstIndex(where: { $0.id == draggedEntryID }),
              entries.indices.contains(targetIndex),
              sourceIndex != targetIndex else { return }

        let dragged = entries[sourceIndex]
        let target = entries[targetIndex]

        switch (dragged, target) {
        case (.app(let dragID), .app(let targetID)):
            // create a new folder from two apps
            let folder = Folder(name: suggestedFolderName(for: [targetID, dragID]),
                                appIDs: [targetID, dragID])
            entries[targetIndex] = .folder(folder)
            entries.remove(at: sourceIndex)

        case (.app(let dragID), .folder(var folder)):
            if !folder.appIDs.contains(dragID) { folder.appIDs.append(dragID) }
            entries[targetIndex] = .folder(folder)
            entries.removeAll { $0.id == draggedEntryID }

        default:
            // dragging a folder onto something -> just reorder instead
            moveEntry(from: sourceIndex, to: targetIndex)
            return
        }
        save()
    }

    func reorderInFolder(_ folderID: String, from: Int, to: Int) {
        for i in entries.indices {
            if case .folder(var f) = entries[i], f.id == folderID {
                guard f.appIDs.indices.contains(from) else { return }
                let item = f.appIDs.remove(at: from)
                let dest = to > from ? to - 1 : to
                f.appIDs.insert(item, at: min(max(dest, 0), f.appIDs.count))
                entries[i] = .folder(f)
                save()
                return
            }
        }
    }

    func addToFolder(appID: String, folderID: String) {
        for i in entries.indices {
            if case .folder(var f) = entries[i], f.id == folderID {
                if !f.appIDs.contains(appID) { f.appIDs.append(appID) }
                entries[i] = .folder(f)
            }
        }
        entries.removeAll { if case .app(let a) = $0 { return a == appID } else { return false } }
        save()
    }

    /// Pull an app out of its folder, dropping it right next to the folder.
    func removeFromFolder(appID: String, folderID: String) {
        guard let fi = entries.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folderID } else { return false }
        }), case .folder(var f) = entries[fi] else { return }

        f.appIDs.removeAll { $0 == appID }
        var insertAt = fi + 1
        if f.appIDs.count <= 1 {
            // dissolve folder: promote remaining app(s), drop folder
            let remaining = f.appIDs
            entries.remove(at: fi)
            for (k, r) in remaining.enumerated() { entries.insert(.app(r), at: fi + k) }
            insertAt = fi + remaining.count
        } else {
            entries[fi] = .folder(f)
        }
        if !entries.contains(where: { if case .app(let a) = $0 { return a == appID } else { return false } }) {
            entries.insert(.app(appID), at: min(insertAt, entries.count))
        }
        save()
    }

    private func removeAppFromFolders(_ id: String) {
        for i in entries.indices {
            if case .folder(var f) = entries[i] {
                f.appIDs.removeAll { $0 == id }
                entries[i] = .folder(f)
            }
        }
        entries = entries.filter { entry in
            if case .folder(let f) = entry { return !f.appIDs.isEmpty }
            return true
        }
    }

    private func suggestedFolderName(for ids: [String]) -> String {
        return "未命名"
    }

    // MARK: - Sorting

    /// Re-order the top-level grid according to the current sort mode.
    /// `custom` keeps the user's saved arrangement.
    func applySort() {
        switch settings.sortMode {
        case 1: // by name
            entries.sort { sortName($0).localizedCaseInsensitiveCompare(sortName($1)) == .orderedAscending }
        case 2: // by date added (newest first)
            entries.sort { sortDate($0) > sortDate($1) }
        default:
            return
        }
        save()
    }

    private func sortName(_ e: LaunchEntry) -> String {
        switch e {
        case .app(let id): return displayName(for: id)
        case .folder(let f): return f.name
        }
    }

    private func sortDate(_ e: LaunchEntry) -> Double {
        switch e {
        case .app(let id): return appIndex[id]?.dateAdded ?? 0
        case .folder(let f): return f.appIDs.compactMap { appIndex[$0]?.dateAdded }.max() ?? 0
        }
    }

    // MARK: - Persistence

    private var supportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LaunchpadPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    func save() {
        var slots: [SavedLayout.Slot] = []
        for entry in entries {
            switch entry {
            case .app(let id):
                slots.append(.init(kind: "app", appID: id, folder: nil))
            case .folder(let folder):
                slots.append(.init(kind: "folder", appID: nil, folder: folder))
            }
        }
        let layout = SavedLayout(slots: slots,
                                 customNames: customNames,
                                 hiddenApps: Array(hiddenApps))
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: supportURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: supportURL),
              let layout = try? JSONDecoder().decode(SavedLayout.self, from: data) else {
            return
        }
        customNames = layout.customNames
        hiddenApps = Set(layout.hiddenApps)
        loadedLayout = layout
    }

    private var loadedLayout: SavedLayout?

    /// Rebuild the top-level entries: honor a saved layout, then append any
    /// newly-installed apps that aren't placed yet.
    private func rebuildEntriesFromLayout(scanned: [AppItem]) {
        var result: [LaunchEntry] = []
        var placed = Set<String>()

        if let layout = loadedLayout {
            for slot in layout.slots {
                if slot.kind == "app", let id = slot.appID, appIndex[id] != nil, !hiddenApps.contains(id) {
                    result.append(.app(id)); placed.insert(id)
                } else if slot.kind == "folder", var folder = slot.folder {
                    folder.appIDs = folder.appIDs.filter { appIndex[$0] != nil && !hiddenApps.contains($0) }
                    if folder.appIDs.count >= 2 {
                        result.append(.folder(folder)); folder.appIDs.forEach { placed.insert($0) }
                    } else if let solo = folder.appIDs.first {
                        result.append(.app(solo)); placed.insert(solo)
                    }
                }
            }
        }

        // Append apps discovered on disk that aren't in the saved layout yet.
        for app in scanned where !placed.contains(app.id) && !hiddenApps.contains(app.id) {
            result.append(.app(app.id))
        }
        entries = result
    }
}
