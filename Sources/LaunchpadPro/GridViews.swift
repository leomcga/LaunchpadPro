import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Root

struct LauncherRootView: View {
    @ObservedObject var model: LaunchModel
    var onDismiss: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .fullScreenUI)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.18).ignoresSafeArea())
                // click on empty backdrop dismisses
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 22) {
                SearchField(text: $model.searchText, focused: $searchFocused)
                    .frame(maxWidth: 520)
                    .padding(.top, 40)

                GridContainer(model: model, onLaunch: { id in
                    model.launch(id)
                    onDismiss()
                })
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 60)

            if let fid = model.openFolderID,
               let folder = currentFolder(fid) {
                FolderOverlay(model: model, folder: folder, onLaunch: { id in
                    model.launch(id); onDismiss()
                })
            }
        }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))
            TextField("搜索", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Grid container (paged or vertical)

struct GridContainer: View {
    @ObservedObject var model: LaunchModel
    var onLaunch: (String) -> Void

    var body: some View {
        let entries = model.displayEntries
        let columns = model.columns
        let searchActive = !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty

        GeometryReader { geo in
            let cell = cellSize(in: geo.size, columns: columns)
            if model.verticalScroll || searchActive {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns(columns), spacing: 26) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            EntryCell(model: model, entry: entry, index: index,
                                      cell: cell, draggable: !searchActive, onLaunch: onLaunch)
                        }
                    }
                    .padding(.vertical, 12)
                }
            } else {
                PagedGrid(model: model, entries: entries, columns: columns,
                          cell: cell, size: geo.size, onLaunch: onLaunch)
            }
        }
    }

    private func gridColumns(_ n: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 18), count: n)
    }

    private func cellSize(in size: CGSize, columns: Int) -> CGSize {
        let w = max(90, (size.width - CGFloat(columns - 1) * 18) / CGFloat(columns))
        return CGSize(width: w, height: model.iconSize + 44)
    }
}

// MARK: - Paged grid (classic Launchpad horizontal pages)

struct PagedGrid: View {
    @ObservedObject var model: LaunchModel
    let entries: [LaunchEntry]
    let columns: Int
    let cell: CGSize
    let size: CGSize
    var onLaunch: (String) -> Void

    @State private var page = 0

    var perPage: Int { max(1, columns * model.rows) }

    var pages: [[(Int, LaunchEntry)]] {
        let indexed = Array(entries.enumerated()).map { ($0.offset, $0.element) }
        return stride(from: 0, to: indexed.count, by: perPage).map {
            Array(indexed[$0 ..< min($0 + perPage, indexed.count)])
        }
    }

    var body: some View {
        let pageList = pages
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pageList.enumerated()), id: \.offset) { pIndex, pageEntries in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns), spacing: 26) {
                            ForEach(pageEntries, id: \.1.id) { index, entry in
                                EntryCell(model: model, entry: entry, index: index,
                                          cell: cell, draggable: true, onLaunch: onLaunch)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(width: size.width, alignment: .top)
                        .id(pIndex)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pageBinding)

            if pageList.count > 1 {
                HStack(spacing: 9) {
                    ForEach(0..<pageList.count, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(i == page ? 0.9 : 0.32))
                            .frame(width: 8, height: 8)
                            .onTapGesture { withAnimation { page = i } }
                    }
                }
                .padding(.bottom, 20)
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

    var body: some View {
        Group {
            switch entry {
            case .app(let id):
                AppIcon(model: model, appID: id, size: model.iconSize, onLaunch: onLaunch)
            case .folder(let folder):
                FolderIcon(model: model, folder: folder, size: model.iconSize)
            }
        }
        .frame(width: cell.width, height: cell.height)
        .modifier(DragReorder(model: model, entry: entry, index: index, enabled: draggable))
    }
}

// MARK: - Drag & drop reordering / folder creation

struct DragReorder: ViewModifier {
    @ObservedObject var model: LaunchModel
    let entry: LaunchEntry
    let index: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    NSItemProvider(object: entry.id as NSString)
                }
                .onDrop(of: [UTType.text], delegate: EntryDropDelegate(model: model, target: entry, targetIndex: index))
        } else {
            content
        }
    }
}

struct EntryDropDelegate: DropDelegate {
    let model: LaunchModel
    let target: LaunchEntry
    let targetIndex: Int

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let draggedID = obj as? String, draggedID != target.id else { return }
            DispatchQueue.main.async {
                // Decide: reorder vs combine into folder.
                switch target {
                case .app:
                    // dropping an app on an app -> folder
                    model.combine(draggedEntryID: draggedID, ontoIndex: currentIndex())
                case .folder:
                    if draggedID.hasPrefix("app:") {
                        let appID = String(draggedID.dropFirst(4))
                        if case .folder(let f) = target {
                            model.addToFolder(appID: appID, folderID: f.id)
                        }
                    } else {
                        reorder(draggedID: draggedID)
                    }
                }
            }
        }
        return true
    }

    private func currentIndex() -> Int {
        model.entries.firstIndex(where: { $0.id == target.id }) ?? targetIndex
    }

    private func reorder(draggedID: String) {
        guard let from = model.entries.firstIndex(where: { $0.id == draggedID }) else { return }
        let to = currentIndex()
        model.moveEntry(from: from, to: to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

// MARK: - App icon

struct AppIcon: View {
    @ObservedObject var model: LaunchModel
    let appID: String
    let size: Double
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
                    .frame(width: size, height: size)
                    .scaleEffect(hovering ? 1.06 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            }
            if renaming {
                TextField("", text: $draft, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: size + 24)
                    .padding(2)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            } else {
                Text(model.displayName(for: appID))
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size + 30)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onLaunch(appID) }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var contextMenu: some View {
        Button("打开") { onLaunch(appID) }
        Button("重命名…") {
            draft = model.displayName(for: appID); renaming = true
        }
        Button("在访达中显示") { model.revealInFinder(appID) }
        Divider()
        Button("隐藏此 App") { model.hide(appID) }
        Button("卸载（移到废纸篓）", role: .destructive) { confirmUninstall() }
    }

    private func commitRename() {
        model.rename(appID, to: draft)
        renaming = false
    }

    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "卸载 “\(model.displayName(for: appID))”？"
        alert.informativeText = "该 App 将被移到废纸篓。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.uninstall(appID)
        }
    }
}

// MARK: - Folder icon (mini grid preview) + expanded overlay

struct FolderIcon: View {
    @ObservedObject var model: LaunchModel
    let folder: Folder
    let size: Double

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(.white.opacity(0.18))
                    .frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(.white.opacity(0.15)))

                let previews = model.appsInFolder(folder).prefix(9)
                let mini = size * 0.24
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: size * 0.05), count: 3),
                          spacing: size * 0.05) {
                    ForEach(Array(previews), id: \.id) { app in
                        Image(nsImage: AppScanner.icon(for: app))
                            .resizable()
                            .frame(width: mini, height: mini)
                    }
                }
                .frame(width: size * 0.82, height: size * 0.82)
            }
            Text(folder.name)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: size + 30)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openFolderID = folder.id }
        .contextMenu {
            Button("重命名文件夹…") { renameFolder() }
        }
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
    let folder: Folder
    var onLaunch: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { model.openFolderID = nil }

            VStack(spacing: 18) {
                Text(folder.name)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)

                let apps = model.appsInFolder(folder)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: min(6, max(1, apps.count))), spacing: 24) {
                    ForEach(apps, id: \.id) { app in
                        AppIcon(model: model, appID: app.id, size: model.iconSize, onLaunch: onLaunch)
                            .contextMenu {
                                Button("打开") { onLaunch(app.id) }
                                Button("移出文件夹") {
                                    model.removeFromFolder(appID: app.id, folderID: folder.id)
                                    if model.appsInFolder(folder).count <= 1 { model.openFolderID = nil }
                                }
                            }
                    }
                }
                .padding(30)
            }
            .padding(40)
            .frame(maxWidth: 900)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12)))
        }
        .transition(.opacity)
    }
}
