import SwiftUI
import AppKit

// MARK: - Cell-frame reporting (for custom drag hit-testing)

struct CellFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private let launcherSpace = "launcher"
private let folderSpace = "folder"
/// Side margin inside each full-width page so icons don't touch the screen edge
/// while pages still slide edge-to-edge.
private let gridSidePad: CGFloat = 52

// MARK: - Root

struct LauncherRootView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void = {}
    var onRescan: () -> Void = {}
    var onQuit: () -> Void = {}

    @FocusState private var searchFocused: Bool
    @State private var appeared = false

    private var topInset: CGFloat {
        max(NSScreen.main?.safeAreaInsets.top ?? 0, 40) + 8
    }

    var body: some View {
        ZStack {
            Color.black.opacity(settings.backgroundDim)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                SearchField(text: $model.searchText, focused: $searchFocused,
                            model: model,
                            onOpenSettings: onOpenSettings, onRescan: onRescan, onQuit: onQuit)
                    .frame(width: 420)

                GridContainer(model: model,
                              onLaunch: { id in model.launch(id); onDismiss() },
                              onDismiss: onDismiss)
            }
            .padding(.top, topInset)
            .padding(.bottom, 20)
            .scaleEffect(appeared ? 1 : 1.04)
            .opacity(appeared ? 1 : 0)

            if let fid = model.openFolderID, let folder = currentFolder(fid) {
                FolderOverlay(model: model, folder: folder, onLaunch: { id in
                    model.launch(id); onDismiss()
                })
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { appeared = true }
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func currentFolder(_ id: String) -> Folder? {
        for e in model.entries { if case .folder(let f) = e, f.id == id { return f } }
        return nil
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    var onOpenSettings: () -> Void = {}
    var onRescan: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            TextField("搜索应用", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
            optionsMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }

    private var optionsMenu: some View {
        Menu {
            Button("设置…") { onOpenSettings() }
            Divider()
            Picker("排序方式", selection: Binding(
                get: { settings.sortMode },
                set: { settings.sortMode = $0; model.applySort() })) {
                Text("自定义").tag(0)
                Text("名称").tag(1)
                Text("添加日期").tag(2)
            }
            Picker("浏览样式", selection: $settings.verticalScroll) {
                Text("分页").tag(false)
                Text("滚动").tag(true)
            }
            Divider()
            Button("重新扫描 App") { onRescan() }
            Button("退出") { onQuit() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22)
    }
}

// MARK: - Grid container (paged or vertical)

struct GridContainer: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        let entries = model.displayEntries
        let columns = settings.columns
        let searchActive = !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty

        GeometryReader { geo in
            let cell = cellSize(in: geo.size, columns: columns)
            if settings.verticalScroll || searchActive {
                ZStack {
                    Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: gridColumns(columns), spacing: 22) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { _, entry in
                                EntryCell(model: model, entry: entry, cell: cell,
                                          isDragging: false, draggable: false,
                                          onLaunch: onLaunch, onDragChanged: { _, _ in }, onDragEnded: { _, _ in })
                            }
                        }
                        .padding(.top, 8).padding(.bottom, 16)
                        .padding(.horizontal, gridSidePad)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            } else {
                PagedGrid(model: model, entries: entries, columns: columns,
                          cell: cell, size: geo.size, onLaunch: onLaunch, onDismiss: onDismiss)
            }
        }
    }

    private func gridColumns(_ n: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: n)
    }

    private func cellSize(in size: CGSize, columns: Int) -> CGSize {
        let usable = size.width - 2 * gridSidePad - CGFloat(columns - 1) * 16
        let w = max(70, usable / CGFloat(columns))
        return CGSize(width: w, height: settings.iconSize + (settings.showLabels ? 34 : 10))
    }
}

// MARK: - Paged grid (offset-driven; custom in-app drag with a floating layer)

struct PagedGrid: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var bus = LauncherBus.shared
    let entries: [LaunchEntry]
    let columns: Int
    let cell: CGSize
    let size: CGSize
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    @State private var page = 0
    @State private var draggingID: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var pageDragOffset: CGFloat = 0

    var perPage: Int { max(1, columns * settings.rows) }

    var pages: [[LaunchEntry]] {
        let chunks = stride(from: 0, to: entries.count, by: perPage).map {
            Array(entries[$0 ..< min($0 + perPage, entries.count)])
        }
        return chunks.isEmpty ? [[]] : chunks
    }

    var body: some View {
        let pageList = pages
        let w = size.width
        let clamped = min(page, max(0, pageList.count - 1))

        ZStack(alignment: .topLeading) {
            VStack(spacing: 14) {
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }

                    HStack(spacing: 0) {
                        ForEach(Array(pageList.enumerated()), id: \.offset) { _, pageEntries in
                            VStack {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 22) {
                                    ForEach(pageEntries, id: \.id) { entry in
                                        EntryCell(model: model, entry: entry, cell: cell,
                                                  isDragging: draggingID == entry.id,
                                                  draggable: true,
                                                  onLaunch: onLaunch,
                                                  onDragChanged: { loc, _ in draggingID = entry.id; dragLocation = loc },
                                                  onDragEnded: { loc, _ in handleDrop(entry.id, at: loc) })
                                    }
                                }
                                .padding(.horizontal, gridSidePad)
                                Spacer(minLength: 0)
                            }
                            .padding(.top, 8)
                            .frame(width: w, alignment: .top)
                        }
                    }
                    .offset(x: -CGFloat(clamped) * w + pageDragOffset)
                }
                .frame(width: w)
                .clipped()

                if pageList.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(0..<pageList.count, id: \.self) { i in
                            Circle()
                                .fill(Color.white.opacity(i == clamped ? 0.95 : 0.35))
                                .frame(width: 7, height: 7)
                                .onTapGesture { withAnimation { page = i } }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }

            // Floating drag icon: on top of everything, never clipped.
            if let did = draggingID, let entry = entryFor(did) {
                entryIcon(entry)
                    .frame(width: cell.width, height: cell.height)
                    .scaleEffect(1.18)
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    .position(dragLocation)
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
        }
        .coordinateSpace(name: launcherSpace)
        .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
        .onChange(of: bus.nextPageTick) { _, _ in
            withAnimation(pageSpring) { page = min(clamped + 1, max(0, pageList.count - 1)) }
        }
        .onChange(of: bus.prevPageTick) { _, _ in
            withAnimation(pageSpring) { page = max(clamped - 1, 0) }
        }
        .onChange(of: bus.scrollTick) { _, _ in
            // Follow the fingers; add resistance past the first/last page.
            var off = pageDragOffset + bus.scrollDX
            if clamped == 0 && off > 0 { off = off * 0.35 }
            if clamped >= pageList.count - 1 && off < 0 { off = off * 0.35 }
            pageDragOffset = off
        }
        .onChange(of: bus.scrollEndTick) { _, _ in
            let d = pageDragOffset
            var newPage = clamped
            if d <= -w * 0.2 { newPage = min(clamped + 1, pageList.count - 1) }
            else if d >= w * 0.2 { newPage = max(clamped - 1, 0) }
            withAnimation(pageSpring) { page = newPage; pageDragOffset = 0 }
        }
    }

    private let pageSpring = Animation.spring(response: 0.34, dampingFraction: 0.86)

    private func entryFor(_ id: String) -> LaunchEntry? {
        model.entries.first { $0.id == id }
    }

    @ViewBuilder private func entryIcon(_ entry: LaunchEntry) -> some View {
        switch entry {
        case .app(let id): AppIcon(model: model, appID: id, onLaunch: { _ in })
        case .folder(let f): FolderIcon(model: model, folder: f)
        }
    }

    private func handleDrop(_ id: String, at loc: CGPoint) {
        defer { draggingID = nil }
        guard let hit = cellFrames.first(where: { $0.key != id && $0.value.contains(loc) }) else { return }
        let targetID = hit.key
        let rect = hit.value
        let relX = (loc.x - rect.minX) / max(rect.width, 1)

        if relX > 0.3 && relX < 0.7 {
            let ti = model.entries.firstIndex { $0.id == targetID } ?? 0
            model.combine(draggedEntryID: id, ontoIndex: ti)
        } else {
            guard let from = model.entries.firstIndex(where: { $0.id == id }) else { return }
            var to = model.entries.firstIndex(where: { $0.id == targetID }) ?? from
            if relX >= 0.7 { to += 1 }
            model.moveEntry(from: from, to: to)
        }
    }
}

// MARK: - A single grid cell (app or folder)

struct EntryCell: View {
    @ObservedObject var model: LaunchModel
    let entry: LaunchEntry
    let cell: CGSize
    var isDragging: Bool
    var draggable: Bool
    var onLaunch: (String) -> Void
    var onDragChanged: (CGPoint, CGSize) -> Void
    var onDragEnded: (CGPoint, CGSize) -> Void

    private var iconView: some View {
        Group {
            switch entry {
            case .app(let id): AppIcon(model: model, appID: id, onLaunch: onLaunch)
            case .folder(let folder): FolderIcon(model: model, folder: folder)
            }
        }
    }

    var body: some View {
        let styled = iconView
            .frame(width: cell.width, height: cell.height)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: CellFramePreference.self,
                                           value: [entry.id: geo.frame(in: .named(launcherSpace))])
                }
            )
            // Leave a dimmed placeholder in the grid while the floating copy drags.
            .opacity(isDragging ? 0.28 : 1)

        if draggable {
            styled.gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named(launcherSpace))
                    .onChanged { v in onDragChanged(v.location, v.translation) }
                    .onEnded { v in onDragEnded(v.location, v.translation) }
            )
        } else {
            styled
        }
    }
}

// MARK: - App icon

struct AppIcon: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    let appID: String
    var onLaunch: (String) -> Void

    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 6) {
            if let item = model.app(for: appID) {
                Image(nsImage: AppScanner.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: settings.iconSize, height: settings.iconSize)
                    .scaleEffect(hovering ? 1.06 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 4)
            }
            if settings.showLabels {
                if renaming {
                    TextField("", text: $draft, onCommit: commitRename)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: settings.iconSize + 30)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Text(model.displayName(for: appID))
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: settings.iconSize + 34)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onLaunch(appID) }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var contextMenu: some View {
        Button("打开") { onLaunch(appID) }
        Button("重命名…") { draft = model.displayName(for: appID); renaming = true }
        Button("在访达中显示") { model.revealInFinder(appID) }
        Divider()
        Button("隐藏此 App") { model.hide(appID) }
        Button("卸载（移到废纸篓）", role: .destructive) { confirmUninstall() }
    }

    private func commitRename() { model.rename(appID, to: draft); renaming = false }

    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "卸载 “\(model.displayName(for: appID))”？"
        alert.informativeText = "该 App 将被移到废纸篓。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { model.uninstall(appID) }
    }
}

// MARK: - Folder tile

struct FolderIcon: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    let folder: Folder

    var body: some View {
        let size = settings.iconSize
        let radius = size * 0.235
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)

                let previews = model.appsInFolder(folder).prefix(9)
                let mini = size * 0.24
                let gap = size * 0.06
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: gap), count: 3), spacing: gap) {
                    ForEach(Array(previews), id: \.id) { app in
                        Image(nsImage: AppScanner.icon(for: app))
                            .resizable()
                            .frame(width: mini, height: mini)
                            .clipShape(RoundedRectangle(cornerRadius: mini * 0.22, style: .continuous))
                    }
                }
                .frame(width: size * 0.78, height: size * 0.78)
            }
            if settings.showLabels {
                Text(folder.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: size + 34)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { model.openFolderID = folder.id } }
    }
}

// MARK: - Expanded folder (with internal drag)

struct FolderOverlay: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    let folder: Folder
    var onLaunch: (String) -> Void

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    @State private var draggingID: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var cellFrames: [String: CGRect] = [:]

    private let cols = 5

    var body: some View {
        let apps = model.appsInFolder(folder)
        let iconSize = min(settings.iconSize, 84)
        let cellW = iconSize + 24
        let cellH = iconSize + 34

        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { close() }

            ZStack(alignment: .topLeading) {
                VStack(spacing: 18) {
                    titleView
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: 18), count: min(cols, max(1, apps.count))), spacing: 20) {
                        ForEach(apps, id: \.id) { app in
                            folderCell(app: app, size: iconSize, cellW: cellW, cellH: cellH)
                        }
                    }
                }
                .padding(36)
                .frame(maxWidth: CGFloat(cols) * (cellW + 18) + 72)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.14)))
                .shadow(color: .black.opacity(0.4), radius: 34, y: 14)

                if let did = draggingID, let app = model.app(for: did) {
                    AppIcon(model: model, appID: app.id, onLaunch: { _ in })
                        .frame(width: cellW, height: cellH)
                        .scaleEffect(1.18)
                        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                        .position(dragLocation)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: folderSpace)
            .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var titleView: some View {
        Group {
            if editingTitle {
                TextField("", text: $titleDraft, onCommit: commitTitle)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .semibold))
                    .focused($titleFocused)
                    .frame(width: 220)
                    .onAppear { titleFocused = true }
            } else {
                Text(folder.name)
                    .font(.system(size: 20, weight: .semibold))
                    .onTapGesture { titleDraft = folder.name; editingTitle = true }
            }
        }
    }

    private func folderCell(app: AppItem, size: CGFloat, cellW: CGFloat, cellH: CGFloat) -> some View {
        AppIcon(model: model, appID: app.id, onLaunch: onLaunch)
            .frame(width: cellW, height: cellH)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: CellFramePreference.self,
                                           value: ["app:" + app.id: geo.frame(in: .named(folderSpace))])
                }
            )
            .opacity(draggingID == app.id ? 0.28 : 1)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named(folderSpace))
                    .onChanged { v in draggingID = app.id; dragLocation = v.location }
                    .onEnded { v in handleFolderDrop(app.id, at: v.location) }
            )
            .contextMenu {
                Button("打开") { onLaunch(app.id) }
                Button("移出文件夹") { pullOut(app.id) }
            }
    }

    private func handleFolderDrop(_ appID: String, at loc: CGPoint) {
        defer { draggingID = nil }
        let key = "app:" + appID
        // Dropped onto another app in the folder -> reorder there.
        if let hit = cellFrames.first(where: { $0.key != key && $0.value.contains(loc) }) {
            let targetAppID = String(hit.key.dropFirst(4))
            let ids = folder.appIDs
            guard let from = ids.firstIndex(of: appID), let to = ids.firstIndex(of: targetAppID) else { return }
            let relX = (loc.x - hit.value.minX) / max(hit.value.width, 1)
            model.reorderInFolder(folder.id, from: from, to: relX >= 0.5 ? to + 1 : to)
        } else {
            // Dropped on empty space inside the panel -> keep; far outside -> pull out.
            // Approximate: if the drop is outside every cell's row area, pull it out.
            let insidePanel = cellFrames.values.contains { $0.insetBy(dx: -80, dy: -80).contains(loc) }
            if !insidePanel { pullOut(appID) }
        }
    }

    private func pullOut(_ appID: String) {
        model.removeFromFolder(appID: appID, folderID: folder.id)
        if model.appsInFolder(folder).count <= 1 { close() }
    }

    private func commitTitle() {
        model.renameFolder(folder.id, to: titleDraft)
        editingTitle = false
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.openFolderID = nil }
    }
}
