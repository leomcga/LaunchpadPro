import AppKit
import SwiftUI

struct CellFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private let verticalGridSpace = "vertical-grid"

struct LauncherRootView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    var onDismiss: () -> Void
    var onOpenSettings: () -> Void
    var onRescan: () -> Void
    var onQuit: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var appeared = false
    @State private var folderChromeHidden = false

    private var topInset: CGFloat {
        max(NSScreen.main?.safeAreaInsets.top ?? 0, 38) + 10
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(settings.backgroundDim)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            LauncherBody(
                model: model,
                topInset: topInset + 54,
                onLaunch: { id in
                    model.launch(id)
                    onDismiss()
                },
                onDismiss: onDismiss
            )
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 1.035)

            SearchBar(
                model: model,
                text: $model.searchText,
                focused: $searchFocused,
                onOpenSettings: onOpenSettings,
                onRescan: onRescan,
                onQuit: onQuit
            )
            .frame(width: 312)
            .padding(.top, topInset)
            .opacity(appeared && !folderChromeHidden ? 1 : 0)
            .blur(radius: folderChromeHidden ? 8 : 0)
            .allowsHitTesting(!folderChromeHidden)
            .animation(.easeInOut(duration: 0.16), value: folderChromeHidden)
        }
        .onAppear {
            folderChromeHidden = model.openFolderID != nil
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                appeared = true
            }
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
        .onChange(of: model.openFolderID) { _, newValue in
            if newValue != nil {
                folderChromeHidden = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    if model.openFolderID == nil {
                        folderChromeHidden = false
                    }
                }
            }
        }
    }
}

private struct LauncherBody: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    let topInset: CGFloat
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    private var isSearching: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            if settings.verticalScroll || isSearching {
                VerticalLauncherGrid(
                    model: model,
                    size: geometry.size,
                    topInset: topInset,
                    onLaunch: onLaunch,
                    onDismiss: onDismiss
                )
            } else {
                PagedLauncherView(
                    model: model,
                    size: geometry.size,
                    topInset: topInset,
                    onLaunch: onLaunch,
                    onDismiss: onDismiss
                )
            }
        }
    }
}

private struct SearchBar: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onOpenSettings: () -> Void
    var onRescan: () -> Void
    var onQuit: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))

                TextField("搜索应用", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .focused(focused)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("设置…") { onOpenSettings() }
                    Divider()
                    Picker("排序方式", selection: Binding(
                        get: { settings.sortMode },
                        set: {
                            settings.sortMode = $0
                            model.applySort()
                        }
                    )) {
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
                    ZStack {
                        Color.white.opacity(0.001)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    .frame(width: 38, height: 30)
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("设置与排序")
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .glassEffect(.regular.tint(Color.white.opacity(0.11)).interactive(), in: .capsule)
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.60),
                                Color.white.opacity(0.18),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 2.2)
                    .blur(radius: 1.2)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
            )
            .shadow(color: .white.opacity(0.10), radius: 1, y: -1)
            .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
        }
    }
}

private struct VerticalLauncherGrid: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    let size: CGSize
    let topInset: CGFloat
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    @State private var folderFrames: [String: CGRect] = [:]
    @State private var draggingID: String?
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String?

    private let sidePadding: CGFloat = 56
    private let columnGap: CGFloat = 16
    private let rowGap: CGFloat = 22

    var body: some View {
        let columns = max(1, settings.columns)
        let cellWidth = max(68, (size.width - sidePadding * 2 - CGFloat(columns - 1) * columnGap) / CGFloat(columns))
        let cellHeight = settings.iconSize + (settings.showLabels ? 36 : 10)
        let folderOpen = model.openFolderID != nil

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: columnGap), count: columns),
                    spacing: rowGap
                ) {
                    ForEach(model.displayEntries) { entry in
                        LauncherEntryView(
                            model: model,
                            entry: entry,
                            cell: CGSize(width: cellWidth, height: cellHeight),
                            isDragging: draggingID == entry.id,
                            isFolderTarget: folderTargetID == entry.id,
                            onLaunch: onLaunch
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CellFramePreference.self,
                                    value: [entry.id: proxy.frame(in: .named(verticalGridSpace))]
                                )
                            }
                        )
                        .highPriorityGesture(verticalDrag(entry))
                    }
                }
                .padding(.top, topInset)
                .padding(.bottom, 34)
                .padding(.horizontal, sidePadding)
            }
            .blur(radius: folderOpen ? 18 : 0)
            .saturation(folderOpen ? 0.72 : 1)
            .brightness(folderOpen ? -0.16 : 0)
            .opacity(folderOpen ? 0.42 : 1)
            .animation(.easeInOut(duration: 0.20), value: folderOpen)
            .onPreferenceChange(CellFramePreference.self) { folderFrames = $0 }

            if let draggingID, let appID = appID(from: draggingID) {
                AppIconView(model: model, appID: appID, onLaunch: { _ in })
                    .frame(width: cellWidth, height: cellHeight)
                    .scaleEffect(1.13)
                    .shadow(color: .black.opacity(0.44), radius: 16, y: 8)
                    .position(dragPoint)
                    .allowsHitTesting(false)
                    .zIndex(40)
                    .blur(radius: folderOpen ? 18 : 0)
                    .opacity(folderOpen ? 0.35 : 1)
            }

            if let folderID = model.openFolderID,
               let folder = currentFolder(folderID) {
                SimpleFolderOverlay(
                    model: model,
                    folder: folder,
                    onLaunch: onLaunch,
                    onClose: {
                        withAnimation(.interpolatingSpring(mass: 0.90, stiffness: 330, damping: 34, initialVelocity: 0)) {
                            model.openFolderID = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.82).combined(with: .opacity),
                    removal: .scale(scale: 0.88).combined(with: .opacity)
                ))
                .zIndex(50)
            }
        }
        .coordinateSpace(name: verticalGridSpace)
    }

    private func currentFolder(_ id: String) -> FolderRecord? {
        model.entries.compactMap(\.folder).first { $0.id == id }
    }

    private func verticalDrag(_ entry: LaunchEntry) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(verticalGridSpace))
            .onChanged { value in
                guard case .app = entry, model.openFolderID == nil else { return }
                draggingID = entry.id
                dragPoint = value.location
                folderTargetID = targetEntryID(at: value.location, excluding: entry.id)
            }
            .onEnded { value in
                guard case .app(let draggedAppID) = entry else {
                    clearDrag()
                    return
                }
                let targetID = folderTargetID ?? targetEntryID(at: value.location, excluding: entry.id)
                if let targetID {
                    if let targetAppID = appID(from: targetID) {
                        model.createFolder(appID: draggedAppID, with: targetAppID)
                    } else if let targetFolderID = folderID(from: targetID) {
                        model.addApp(draggedAppID, toFolder: targetFolderID)
                    }
                }
                clearDrag()
            }
    }

    private func targetEntryID(at point: CGPoint, excluding id: String) -> String? {
        for (entryID, frame) in folderFrames where entryID != id {
            let hitRect = CGRect(
                x: frame.midX - frame.width * 0.40,
                y: frame.midY - frame.height * 0.40,
                width: frame.width * 0.80,
                height: frame.height * 0.80
            )
            if hitRect.contains(point) {
                return entryID
            }
        }
        return nil
    }

    private func appID(from entryID: String) -> String? {
        guard entryID.hasPrefix("app:") else { return nil }
        return String(entryID.dropFirst(4))
    }

    private func folderID(from entryID: String) -> String? {
        guard entryID.hasPrefix("folder:") else { return nil }
        return String(entryID.dropFirst(7))
    }

    private func clearDrag() {
        draggingID = nil
        folderTargetID = nil
    }
}

struct LauncherEntryView: View {
    @ObservedObject var model: LaunchModel

    let entry: LaunchEntry
    let cell: CGSize
    var isDragging: Bool
    var isFolderTarget: Bool
    var onLaunch: (String) -> Void

    var body: some View {
        Group {
            switch entry {
            case .app(let appID):
                AppIconView(model: model, appID: appID, onLaunch: onLaunch)
            case .folder(let folder):
                FolderIconView(model: model, folder: folder)
            }
        }
        .frame(width: cell.width, height: cell.height)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(isFolderTarget ? 0.22 : 0))
                .scaleEffect(isFolderTarget ? 1 : 0.64)
                .opacity(isFolderTarget ? 1 : 0)
        )
        .scaleEffect(isFolderTarget ? 0.92 : 1)
        .opacity(isDragging ? 0.30 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.76), value: isFolderTarget)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }
}

struct AppIconView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    let appID: String
    var onLaunch: (String) -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var iconImage: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: settings.iconSize, height: settings.iconSize)
                    .scaleEffect(isHovering ? 1.06 : 1)
                    .shadow(color: .black.opacity(0.30), radius: 7, y: 4)
                    .animation(.spring(response: 0.22, dampingFraction: 0.74), value: isHovering)
            } else {
                RoundedRectangle(cornerRadius: settings.iconSize * 0.22, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .frame(width: settings.iconSize, height: settings.iconSize)
            }

            if settings.showLabels {
                if isRenaming {
                    TextField("", text: $draftName)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: settings.iconSize + 36)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .onSubmit { commitRename() }
                } else {
                    Text(model.displayName(for: appID))
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: settings.iconSize + 38)
                        .shadow(color: .black.opacity(0.72), radius: 3, y: 1)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onLaunch(appID) }
        .contextMenu { appMenu }
        .onAppear { loadIcon() }
        .onChange(of: appID) { _, _ in loadIcon() }
    }

    @ViewBuilder private var appMenu: some View {
        Button("打开") { onLaunch(appID) }
        Button("新建文件夹…") { createFolderFromMenu() }
            .disabled(model.topLevelAppCandidates(excluding: appID).isEmpty)
        let folders = model.folderChoices(for: appID)
        if !folders.isEmpty {
            Menu("加入文件夹") {
                ForEach(folders, id: \.id) { folder in
                    Button(folder.name) { model.addApp(appID, toFolder: folder.id) }
                }
            }
        }
        Button("重命名…") {
            draftName = model.displayName(for: appID)
            isRenaming = true
        }
        Button("在访达中显示") { model.revealInFinder(appID) }
        Divider()
        Button("隐藏此 App") { model.hide(appID) }
        Button("卸载（移到废纸篓）", role: .destructive) { confirmUninstall() }
    }

    private func commitRename() {
        model.rename(appID, to: draftName)
        isRenaming = false
    }

    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "卸载 “\(model.displayName(for: appID))”？"
        alert.informativeText = "该 App 会被移到废纸篓。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.uninstall(appID)
        }
    }

    private func createFolderFromMenu() {
        let candidates = model.topLevelAppCandidates(excluding: appID)
        guard !candidates.isEmpty else {
            NSSound.beep()
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for app in candidates {
            popup.addItem(withTitle: model.displayName(for: app.id))
            popup.lastItem?.representedObject = app.id
        }

        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "选择另一个 App，与 “\(model.displayName(for: appID))” 放进同一个文件夹。"
        alert.accessoryView = popup
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn,
           let targetID = popup.selectedItem?.representedObject as? String {
            model.createFolder(appID: appID, with: targetID)
        }
    }

    private func loadIcon() {
        guard let app = model.app(for: appID) else {
            iconImage = nil
            return
        }
        iconImage = AppScanner.icon(for: app)
    }
}

struct FolderIconView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    let folder: FolderRecord

    var body: some View {
        let size = settings.iconSize * 0.88
        let previewApps = Array(model.apps(in: folder).prefix(9))
        let mini = size * 0.195
        let gap = size * 0.080
        let gridSide = mini * 3 + gap * 2

        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                    .fill(Color.white.opacity(0.001))
                    .frame(width: size, height: size)
                    .glassEffect(.regular.tint(Color.white.opacity(0.13)).interactive(), in: .rect(cornerRadius: size * 0.235))
                    .overlay(folderTint(size: size))
                    .overlay(folderHighlight(size: size))
                    .shadow(color: .white.opacity(0.12), radius: 2, y: -1)
                    .shadow(color: .black.opacity(0.28), radius: 13, y: 8)

                ZStack {
                    ForEach(Array(previewApps.enumerated()), id: \.element.id) { index, app in
                        Image(nsImage: AppScanner.icon(for: app))
                            .resizable()
                            .frame(width: mini, height: mini)
                            .clipShape(RoundedRectangle(cornerRadius: mini * 0.23, style: .continuous))
                            .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
                            .position(previewPosition(index: index, mini: mini, gap: gap))
                    }
                }
                .frame(width: gridSide, height: gridSide)
                .allowsHitTesting(false)
            }

            if settings.showLabels {
                Text(folder.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: size + 38)
                    .shadow(color: .black.opacity(0.68), radius: 3, y: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                model.openFolderID = folder.id
            }
        }
        .contextMenu {
            Button("打开文件夹") {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    model.openFolderID = folder.id
                }
            }
            Button("重命名…") { renameFolder() }
        }
    }

    private func renameFolder() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = folder.name

        let alert = NSAlert()
        alert.messageText = "重命名文件夹"
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            model.renameFolder(folder.id, to: field.stringValue)
        }
    }

    private func folderTint(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.02),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func folderHighlight(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.58),
                        Color.white.opacity(0.18),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func previewPosition(index: Int, mini: CGFloat, gap: CGFloat) -> CGPoint {
        let column = CGFloat(index % 3)
        let row = CGFloat(index / 3)
        return CGPoint(
            x: mini / 2 + column * (mini + gap),
            y: mini / 2 + row * (mini + gap)
        )
    }
}

struct SimpleFolderOverlay: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    let folder: FolderRecord
    var onLaunch: (String) -> Void
    var onClose: () -> Void

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var frames: [String: CGRect] = [:]
    @State private var draggingID: String?
    @State private var dragPoint: CGPoint = .zero
    @FocusState private var titleFocused: Bool

    private let coordinateSpace = "simple-folder"

    var body: some View {
        let apps = model.apps(in: folder)
        let icon = min(settings.iconSize, 86)
        let cell = CGSize(width: icon + 26, height: icon + 38)
        let columns = min(10, max(1, apps.count))
        let rowCount = max(1, Int(ceil(Double(apps.count) / Double(columns))))
        let horizontalSpacing: CGFloat = 18
        let verticalSpacing: CGFloat = 18
        let availableWidth = (NSScreen.main?.frame.width ?? 1100) - 112
        let panelWidth = min(
            availableWidth,
            max(560, CGFloat(columns) * cell.width + CGFloat(columns - 1) * horizontalSpacing + 54)
        )
        let panelHeight = CGFloat(rowCount) * cell.height + CGFloat(rowCount - 1) * verticalSpacing + 42

        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 16) {
                titleView

                GlassEffectContainer(spacing: 0) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cell.width), spacing: horizontalSpacing), count: columns),
                        spacing: verticalSpacing
                    ) {
                        ForEach(apps, id: \.id) { app in
                            AppIconView(model: model, appID: app.id, onLaunch: onLaunch)
                                .frame(width: cell.width, height: cell.height)
                                .opacity(draggingID == app.id ? 0.28 : 1)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: CellFramePreference.self,
                                            value: ["app:" + app.id: proxy.frame(in: .named(coordinateSpace))]
                                        )
                                    }
                                )
                                .gesture(folderDrag(appID: app.id))
                                .contextMenu {
                                    Button("打开") { onLaunch(app.id) }
                                    Button("移出文件夹") {
                                        model.removeFromFolder(appID: app.id, folderID: folder.id)
                                        if model.apps(in: folder).count <= 1 { onClose() }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 27)
                    .padding(.vertical, 21)
                    .frame(width: panelWidth, height: panelHeight)
                    .glassEffect(.regular.tint(Color.black.opacity(0.18)).interactive(false), in: .rect(cornerRadius: 28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.56),
                                        Color.white.opacity(0.16),
                                        Color.black.opacity(0.26)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: CellFramePreference.self,
                                value: ["folder:panel": proxy.frame(in: .named(coordinateSpace))]
                            )
                        }
                    )
                    .shadow(color: .white.opacity(0.12), radius: 2, y: -1)
                    .shadow(color: .black.opacity(0.46), radius: 34, y: 16)
                }
            }
            .padding(.horizontal, 56)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.82).combined(with: .opacity),
                removal: .scale(scale: 0.90).combined(with: .opacity)
            ))

            if let draggingID {
                AppIconView(model: model, appID: draggingID, onLaunch: { _ in })
                    .frame(width: cell.width, height: cell.height)
                    .scaleEffect(1.15)
                    .shadow(color: .black.opacity(0.46), radius: 16, y: 8)
                    .position(dragPoint)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: coordinateSpace)
        .onPreferenceChange(CellFramePreference.self) { frames = $0 }
    }

    @ViewBuilder private var titleView: some View {
        if editingTitle {
            TextField("", text: $titleDraft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: 230)
                .focused($titleFocused)
                .onAppear { titleFocused = true }
                .onSubmit { commitTitle() }
        } else {
            Text(folder.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.42), radius: 6, y: 2)
                .onTapGesture {
                    titleDraft = folder.name
                    editingTitle = true
                }
        }
    }

    private func folderDrag(appID: String) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                draggingID = appID
                dragPoint = value.location
            }
            .onEnded { value in
                finishDrag(appID: appID, at: value.location)
            }
    }

    private func finishDrag(appID: String, at point: CGPoint) {
        defer { draggingID = nil }

        let sourceKey = "app:" + appID
        guard let hit = frames.first(where: {
            $0.key.hasPrefix("app:") && $0.key != sourceKey && $0.value.contains(point)
        }) else {
            if let panel = frames["folder:panel"], panel.insetBy(dx: -30, dy: -30).contains(point) {
                return
            }
            model.removeFromFolder(appID: appID, folderID: folder.id)
            onClose()
            return
        }

        let targetID = String(hit.key.dropFirst(4))
        guard let source = folder.appIDs.firstIndex(of: appID),
              let target = folder.appIDs.firstIndex(of: targetID) else { return }
        let rightHalf = point.x > hit.value.midX
        model.reorderInFolder(folder.id, from: source, to: rightHalf ? target + 1 : target)
    }

    private func commitTitle() {
        model.renameFolder(folder.id, to: titleDraft)
        editingTitle = false
    }
}
