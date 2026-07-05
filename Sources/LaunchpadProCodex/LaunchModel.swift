import AppKit
import Combine
import SwiftUI

@MainActor
final class LaunchModel: ObservableObject {
    @Published private(set) var apps: [AppRecord] = []
    @Published var entries: [LaunchEntry] = []
    @Published var searchText: String = ""
    @Published var openFolderID: String?

    @Published private(set) var customNames: [String: String] = [:]
    @Published private(set) var hiddenApps: Set<String> = []
    @Published private(set) var layoutMemories: [LayoutMemory] = []

    private(set) var pageArrangement: [[String]] = []
    private var appIndex: [String: AppRecord] = [:]
    private var loadedLayout: SavedLayout?

    let settings = AppSettings.shared

    init() {
        reload()
    }

    func reload() {
        let scanned = AppScanner.scan()
        apps = scanned
        appIndex = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, $0) })
        load()
        rebuildEntries(scanned)
        applySort()
    }

    func app(for id: String) -> AppRecord? {
        appIndex[id]
    }

    func displayName(for id: String) -> String {
        if let custom = customNames[id], !custom.isEmpty { return custom }
        return appIndex[id]?.name ?? id
    }

    var visibleApps: [AppRecord] {
        apps.filter { !hiddenApps.contains($0.id) }
    }

    var folders: [FolderRecord] {
        entries.compactMap(\.folder)
    }

    var displayEntries: [LaunchEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty else {
            return visibleApps
                .filter { displayName(for: $0.id).lowercased().contains(query) }
                .map { .app($0.id) }
        }

        return sanitize(entries)
    }

    func apps(in folder: FolderRecord) -> [AppRecord] {
        folder.appIDs.compactMap { id in
            guard !hiddenApps.contains(id) else { return nil }
            return appIndex[id]
        }
    }

    func launch(_ id: String) {
        guard let app = appIndex[id] else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, _ in }
    }

    func revealInFinder(_ id: String) {
        guard let app = appIndex[id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == appIndex[id]?.originalName {
            customNames.removeValue(forKey: id)
        } else {
            customNames[id] = trimmed
        }
        save()
        objectWillChange.send()
    }

    func renameFolder(_ folderID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        entries = entries.map { entry in
            guard case .folder(var folder) = entry, folder.id == folderID else { return entry }
            folder.name = trimmed
            return .folder(folder)
        }
        save()
    }

    func hide(_ id: String) {
        hiddenApps.insert(id)
        removeAppFromFolders(id)
        entries.removeAll { $0.appID == id }
        pageArrangement = pageArrangement
            .map { $0.filter { $0 != "app:" + id } }
            .filter { !$0.isEmpty }
        save()
        objectWillChange.send()
    }

    func unhide(_ id: String) {
        hiddenApps.remove(id)
        if appIndex[id] != nil && !entries.contains(where: { $0.appID == id }) {
            entries.append(.app(id))
        }
        save()
        objectWillChange.send()
    }

    func unhideAll() {
        hiddenApps.removeAll()
        rebuildEntries(apps)
        save()
    }

    func uninstall(_ id: String) {
        guard let app = appIndex[id] else { return }
        do {
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            hiddenApps.remove(id)
            removeAppFromFolders(id)
            entries.removeAll { $0.appID == id }
            apps.removeAll { $0.id == id }
            appIndex.removeValue(forKey: id)
            save()
        } catch {
            NSSound.beep()
        }
    }

    func resetLayout() {
        customNames.removeAll()
        hiddenApps.removeAll()
        pageArrangement.removeAll()
        loadedLayout = nil
        entries = apps.map { .app($0.id) }
        settings.sortMode = 0
        save()
    }

    func layoutMemory(slot: Int) -> LayoutMemory? {
        layoutMemories.first { $0.slot == slot }
    }

    func saveLayoutMemory(slot: Int) {
        guard (0..<3).contains(slot) else { return }

        let memory = LayoutMemory(
            slot: slot,
            savedAt: Date().timeIntervalSince1970,
            slots: currentSlots(),
            customNames: customNames,
            hiddenApps: Array(hiddenApps),
            pageIDs: pageArrangement
        )

        var next = layoutMemories.filter { $0.slot != slot }
        next.append(memory)
        layoutMemories = next
            .filter { (0..<3).contains($0.slot) }
            .sorted { $0.slot < $1.slot }
        save()
    }

    @discardableResult
    func restoreLayoutMemory(slot: Int) -> Bool {
        guard let memory = layoutMemory(slot: slot) else {
            NSSound.beep()
            return false
        }

        customNames = memory.customNames
        hiddenApps = Set(memory.hiddenApps)
        pageArrangement = memory.pageIDs
        loadedLayout = SavedLayout(
            slots: memory.slots,
            customNames: memory.customNames,
            hiddenApps: memory.hiddenApps,
            pageIDs: memory.pageIDs,
            layoutMemories: layoutMemories
        )
        rebuildEntries(apps)
        settings.sortMode = 0
        save()
        objectWillChange.send()
        return true
    }

    func deleteLayoutMemory(slot: Int) {
        layoutMemories.removeAll { $0.slot == slot }
        save()
    }

    func applySort() {
        switch settings.sortMode {
        case 1:
            entries = sanitize(entries).sorted {
                sortName($0).localizedCaseInsensitiveCompare(sortName($1)) == .orderedAscending
            }
            pageArrangement.removeAll()
            save()
        case 2:
            entries = sanitize(entries).sorted { sortDate($0) > sortDate($1) }
            pageArrangement.removeAll()
            save()
        default:
            entries = sanitize(entries)
        }
    }

    func commitPages(_ pages: [[LaunchEntry]]) {
        var cleaned = pages.map { sanitize($0) }.filter { !$0.isEmpty }
        if cleaned.isEmpty { cleaned = [[]] }
        pageArrangement = cleaned.map { $0.map(\.id) }
        entries = cleaned.flatMap { $0 }
        settings.sortMode = 0
        save()
    }

    func updateFolder(_ folder: FolderRecord) {
        entries = entries.map { entry in
            if case .folder(let current) = entry, current.id == folder.id {
                return .folder(folder)
            }
            return entry
        }
        save()
    }

    func topLevelAppCandidates(excluding appID: String) -> [AppRecord] {
        entries.compactMap { entry in
            guard case .app(let id) = entry, id != appID else { return nil }
            guard !hiddenApps.contains(id) else { return nil }
            return appIndex[id]
        }
    }

    func folderChoices(for appID: String) -> [FolderRecord] {
        folders.filter { !$0.appIDs.contains(appID) }
    }

    @discardableResult
    func createFolder(appID: String, with targetAppID: String) -> Bool {
        guard appID != targetAppID,
              appIndex[appID] != nil,
              appIndex[targetAppID] != nil,
              entries.contains(where: { $0.appID == appID }),
              let targetIndex = entries.firstIndex(where: { $0.appID == targetAppID }) else {
            NSSound.beep()
            return false
        }

        let folder = FolderRecord(name: "未命名", appIDs: [targetAppID, appID])
        var next = entries
        next[targetIndex] = .folder(folder)
        next.removeAll { $0.appID == appID }
        entries = next

        replacePageID("app:" + targetAppID, with: "folder:" + folder.id)
        removePageID("app:" + appID)
        save()
        return true
    }

    @discardableResult
    func addApp(_ appID: String, toFolder folderID: String) -> Bool {
        guard appIndex[appID] != nil else {
            NSSound.beep()
            return false
        }

        var next = entries
        var didAdd = false

        for index in next.indices {
            guard case .folder(var folder) = next[index] else { continue }
            folder.appIDs.removeAll { $0 == appID }
            if folder.id == folderID {
                folder.appIDs.append(appID)
                didAdd = true
            }
            next[index] = .folder(folder)
        }

        guard didAdd else {
            NSSound.beep()
            return false
        }

        next.removeAll { $0.appID == appID }
        entries = sanitize(next)
        removePageID("app:" + appID)
        save()
        return true
    }

    func reorderInFolder(_ folderID: String, from source: Int, to destination: Int) {
        guard source != destination else { return }
        entries = entries.map { entry in
            guard case .folder(var folder) = entry, folder.id == folderID,
                  folder.appIDs.indices.contains(source) else { return entry }
            let item = folder.appIDs.remove(at: source)
            let adjusted = destination > source ? destination - 1 : destination
            folder.appIDs.insert(item, at: min(max(adjusted, 0), folder.appIDs.count))
            return .folder(folder)
        }
        save()
    }

    func removeFromFolder(appID: String, folderID: String) {
        removeFromFolder(appID: appID, folderID: folderID, reinsertRemovedApp: true)
    }

    func detachFromFolderForLayout(appID: String, folderID: String) {
        removeFromFolder(appID: appID, folderID: folderID, reinsertRemovedApp: false)
    }

    private func removeFromFolder(appID: String, folderID: String, reinsertRemovedApp: Bool) {
        guard let folderIndex = entries.firstIndex(where: {
            if case .folder(let folder) = $0 { return folder.id == folderID }
            return false
        }), case .folder(var folder) = entries[folderIndex] else { return }

        folder.appIDs.removeAll { $0 == appID }
        let insertAt: Int

        if folder.appIDs.count <= 1 {
            let remaining = folder.appIDs.map { LaunchEntry.app($0) }
            entries.remove(at: folderIndex)
            entries.insert(contentsOf: remaining, at: folderIndex)
            insertAt = folderIndex + remaining.count
            if let only = folder.appIDs.first {
                replacePageID("folder:" + folderID, with: "app:" + only)
            } else {
                removePageID("folder:" + folderID)
            }
        } else {
            entries[folderIndex] = .folder(folder)
            insertAt = folderIndex + 1
        }

        if reinsertRemovedApp, appIndex[appID] != nil, !entries.contains(where: { $0.appID == appID }) {
            entries.insert(.app(appID), at: min(insertAt, entries.count))
        }
        save()
    }

    private func removeAppFromFolders(_ appID: String) {
        entries = entries.compactMap { entry in
            guard case .folder(var folder) = entry else { return entry }
            folder.appIDs.removeAll { $0 == appID }
            if folder.appIDs.count >= 2 { return .folder(folder) }
            if let only = folder.appIDs.first { return .app(only) }
            return nil
        }
    }

    private func replacePageID(_ oldID: String, with newID: String) {
        pageArrangement = pageArrangement.map { page in
            page.map { $0 == oldID ? newID : $0 }
        }
    }

    private func removePageID(_ id: String) {
        pageArrangement = pageArrangement
            .map { page in page.filter { $0 != id } }
            .filter { !$0.isEmpty }
    }

    private func sortName(_ entry: LaunchEntry) -> String {
        switch entry {
        case .app(let appID):
            return displayName(for: appID)
        case .folder(let folder):
            return folder.name
        }
    }

    private func sortDate(_ entry: LaunchEntry) -> Double {
        switch entry {
        case .app(let appID):
            return appIndex[appID]?.dateAdded ?? 0
        case .folder(let folder):
            return folder.appIDs.compactMap { appIndex[$0]?.dateAdded }.max() ?? 0
        }
    }

    private func sanitize(_ source: [LaunchEntry]) -> [LaunchEntry] {
        source.compactMap { entry in
            switch entry {
            case .app(let appID):
                guard appIndex[appID] != nil, !hiddenApps.contains(appID) else { return nil }
                return entry
            case .folder(var folder):
                folder.appIDs = folder.appIDs.filter { appIndex[$0] != nil && !hiddenApps.contains($0) }
                if folder.appIDs.count >= 2 { return .folder(folder) }
                if let only = folder.appIDs.first { return .app(only) }
                return nil
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: layoutURL),
              let layout = try? JSONDecoder().decode(SavedLayout.self, from: data) else {
            loadedLayout = nil
            return
        }
        customNames = layout.customNames
        hiddenApps = Set(layout.hiddenApps)
        pageArrangement = layout.pageIDs
        layoutMemories = (layout.layoutMemories ?? [])
            .filter { (0..<3).contains($0.slot) }
            .sorted { $0.slot < $1.slot }
        loadedLayout = layout
    }

    private func rebuildEntries(_ scanned: [AppRecord]) {
        var result: [LaunchEntry] = []
        var placedApps = Set<String>()

        if let layout = loadedLayout {
            for slot in layout.slots {
                switch slot.kind {
                case "app":
                    guard let id = slot.appID,
                          appIndex[id] != nil,
                          !hiddenApps.contains(id),
                          !placedApps.contains(id) else { continue }
                    result.append(.app(id))
                    placedApps.insert(id)
                case "folder":
                    guard var folder = slot.folder else { continue }
                    folder.appIDs = folder.appIDs.filter {
                        appIndex[$0] != nil && !hiddenApps.contains($0) && !placedApps.contains($0)
                    }
                    if folder.appIDs.count >= 2 {
                        folder.appIDs.forEach { placedApps.insert($0) }
                        result.append(.folder(folder))
                    } else if let single = folder.appIDs.first {
                        placedApps.insert(single)
                        result.append(.app(single))
                    }
                default:
                    continue
                }
            }
        }

        for app in scanned where !hiddenApps.contains(app.id) && !placedApps.contains(app.id) {
            result.append(.app(app.id))
        }

        entries = sanitize(result)
    }

    private func save() {
        let layout = SavedLayout(
            slots: currentSlots(),
            customNames: customNames,
            hiddenApps: Array(hiddenApps),
            pageIDs: pageArrangement,
            layoutMemories: layoutMemories
        )

        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: layoutURL, options: .atomic)
        }
    }

    private func currentSlots() -> [SavedLayout.Slot] {
        entries.map { entry -> SavedLayout.Slot in
            switch entry {
            case .app(let appID):
                return .init(kind: "app", appID: appID, folder: nil)
            case .folder(let folder):
                return .init(kind: "folder", appID: nil, folder: folder)
            }
        }
    }

    private var layoutURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = root.appendingPathComponent("LaunchpadPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let current = folder.appendingPathComponent("layout.json")

        let legacy = root
            .appendingPathComponent("LaunchpadProCodex", isDirectory: true)
            .appendingPathComponent("layout.json")
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: current)
        }

        return current
    }
}
