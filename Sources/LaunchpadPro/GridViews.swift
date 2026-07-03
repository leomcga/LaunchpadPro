import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

    var body: some View {
        ZStack {
            // The frosted blur itself lives on the window (single continuous
            // layer -> no seam between pages). Here we only add a uniform dim
            // for text legibility, and catch taps on empty space to dismiss.
            Color.black.opacity(settings.backgroundDim)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 22) {
                SearchField(text: $model.searchText, focused: $searchFocused,
                            model: model,
                            onOpenSettings: onOpenSettings, onRescan: onRescan, onQuit: onQuit)
                    .frame(width: 420)
                    .padding(.top, 30)

                GridContainer(model: model, onLaunch: { id in
                    model.launch(id); onDismiss()
                })
            }
            .padding(.horizontal, 60)
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

    var body: some View {
        let entries = model.displayEntries
        let columns = settings.columns
        let searchActive = !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty

        GeometryReader { geo in
            let cell = cellSize(in: geo.size, columns: columns)
            if settings.verticalScroll || searchActive {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns(columns), spacing: 22) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            EntryCell(model: model, entry: entry, index: index,
                                      cell: cell, draggable: !searchActive, onLaunch: onLaunch)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                PagedGrid(model: model, entries: entries, columns: columns,
                          cell: cell, size: geo.size, onLaunch: onLaunch)
            }
        }
    }

    private func gridColumns(_ n: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: n)
    }

    private func cellSize(in size: CGSize, columns: Int) -> CGSize {
        let w = max(70, (size.width - CGFloat(columns - 1) * 16) / CGFloat(columns))
        return CGSize(width: w, height: settings.iconSize + (settings.showLabels ? 34 : 10))
    }
}

// MARK: - Paged grid (classic Launchpad horizontal pages)

struct PagedGrid: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    let entries: [LaunchEntry]
    let columns: Int
    let cell: CGSize
    let size: CGSize
    var onLaunch: (String) -> Void

    @State private var page = 0

    var perPage: Int { max(1, columns * settings.rows) }

    var pages: [[(Int, LaunchEntry)]] {
        let indexed = Array(entries.enumerated()).map { ($0.offset, $0.element) }
        let chunks = stride(from: 0, to: indexed.count, by: perPage).map {
            Array(indexed[$0 ..< min($0 + perPage, indexed.count)])
        }
        return chunks.isEmpty ? [[]] : chunks
    }

    var body: some View {
        let pageList = pages
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pageList.enumerated()), id: \.offset) { pIndex, pageEntries in
                        VStack {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 22) {
                                ForEach(pageEntries, id: \.1.id) { index, entry in
                                    EntryCell(model: model, entry: entry, index: index,
                                              cell: cell, draggable: true, onLaunch: onLaunch)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 10)
                        .frame(width: size.width)
                        .id(pIndex)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pageBinding)

            if pageList.count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<pageList.count, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(i == page ? 0.95 : 0.35))
                            .frame(width: 7, height: 7)
                            .onTapGesture { withAnimation(.easeInOut) { page = i } }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var pageBinding: Binding<Int?> {
        Binding(get: { page }, set: { if let v = $0 { page = v } })
    }
}

// MARK: - A single grid cell (app or folder), draggable

struct EntryCell: View {
    @ObservedObject var model: LaunchModel
    let entry: LaunchEntry
    let index: Int
    let cell: CGSize
    var draggable: Bool
    var onLaunch: (String) -> Void

    @State private var dropTargeted = false

    var body: some View {
        Group {
            switch entry {
            case .app(let id):
                AppIcon(model: model, appID: id, onLaunch: onLaunch)
            case .folder(let folder):
                FolderIcon(model: model, folder: folder)
            }
        }
        .frame(width: cell.width, height: cell.height)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(dropTargeted ? 0.16 : 0))
        )
        .modifier(DragReorder(model: model, entry: entry, cellWidth: cell.width,
                              enabled: draggable, targeted: $dropTargeted))
    }
}

// MARK: - Drag & drop reordering / folder creation

struct DragReorder: ViewModifier {
    @ObservedObject var model: LaunchModel
    let entry: LaunchEntry
    let cellWidth: CGFloat
    let enabled: Bool
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { NSItemProvider(object: entry.id as NSString) }
                .onDrop(of: [UTType.text],
                        delegate: EntryDropDelegate(model: model, target: entry,
                                                    cellWidth: cellWidth, targeted: $targeted))
        } else {
            content
        }
    }
}

struct EntryDropDelegate: DropDelegate {
    let model: LaunchModel
    let target: LaunchEntry
    let cellWidth: CGFloat
    @Binding var targeted: Bool

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        // Center third of the icon => combine into a folder. Left/right thirds
        // => reorder before/after (mirrors Launchpad's edge-vs-center behavior).
        let x = info.location.x
        let combineZone = x > cellWidth * 0.3 && x < cellWidth * 0.7
        let dropAfter = x >= cellWidth * 0.7

        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let draggedID = obj as? String, draggedID != target.id else { return }
            DispatchQueue.main.async {
                let targetIndex = model.entries.firstIndex(where: { $0.id == target.id }) ?? 0

                if combineZone, case .app = target {
                    model.combine(draggedEntryID: draggedID, ontoIndex: targetIndex)
                } else if combineZone, case .folder(let f) = target, draggedID.hasPrefix("app:") {
                    model.addToFolder(appID: String(draggedID.dropFirst(4)), folderID: f.id)
                } else {
                    guard let from = model.entries.firstIndex(where: { $0.id == draggedID }) else { return }
                    var to = model.entries.firstIndex(where: { $0.id == target.id }) ?? from
                    if dropAfter { to += 1 }
                    model.moveEntry(from: from, to: to)
                }
            }
        }
        return true
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
        VStack(spacing: 7) {
            if let item = model.app(for: appID) {
                Image(nsImage: AppScanner.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: settings.iconSize, height: settings.iconSize)
                    .scaleEffect(hovering ? 1.08 : 1.0)
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
                        .font(.system(size: 12.5))
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

// MARK: - Folder icon (mini grid preview) + expanded overlay

struct FolderIcon: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    let folder: Folder

    var body: some View {
        let size = settings.iconSize
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23)
                    .fill(.white.opacity(0.16))
                    .frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.23).stroke(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 3)

                let previews = model.appsInFolder(folder).prefix(9)
                let mini = size * 0.235
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: size * 0.05), count: 3),
                          spacing: size * 0.05) {
                    ForEach(Array(previews), id: \.id) { app in
                        Image(nsImage: AppScanner.icon(for: app))
                            .resizable().frame(width: mini, height: mini)
                    }
                }
                .frame(width: size * 0.8, height: size * 0.8)
            }
            if settings.showLabels {
                Text(folder.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: size + 34)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.openFolderID = folder.id } }
        .contextMenu { Button("重命名文件夹…") { renameFolder() } }
    }

    private func renameFolder() {
        let alert = NSAlert()
        alert.messageText = "重命名文件夹"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = folder.name
        alert.accessoryView = field
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.renameFolder(folder.id, to: field.stringValue)
        }
    }
}

struct FolderOverlay: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    let folder: Folder
    var onLaunch: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { model.openFolderID = nil }

            VStack(spacing: 20) {
                Text(folder.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                let apps = model.appsInFolder(folder)
                let cols = min(6, max(1, apps.count))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: cols), spacing: 26) {
                    ForEach(apps, id: \.id) { app in
                        AppIcon(model: model, appID: app.id, onLaunch: onLaunch)
                            .contextMenu {
                                Button("打开") { onLaunch(app.id) }
                                Button("移出文件夹") {
                                    model.removeFromFolder(appID: app.id, folderID: folder.id)
                                    if model.appsInFolder(folder).count <= 1 { model.openFolderID = nil }
                                }
                            }
                    }
                }
                .padding(34)
            }
            .padding(44)
            .frame(maxWidth: 940)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}
