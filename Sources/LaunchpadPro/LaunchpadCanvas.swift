import SwiftUI
import AppKit

private struct PlacedItem: Identifiable {
    let page: Int
    let index: Int
    let entry: LaunchEntry
    var id: String { entry.id }
}

/// A per-page launcher canvas. Each page is its own packed list; pages may be
/// non-full and empty pages disappear automatically. Dragging reflows items and
/// only spills a genuine overflow to the next page — so pages are created and
/// destroyed naturally as apps move (like the native Launchpad).
struct LaunchpadCanvas: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var bus = LauncherBus.shared
    let size: CGSize
    var topInset: CGFloat = 8   // push the grid below the floating search bar
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    @State private var pages: [[LaunchEntry]] = []
    @State private var page = 0
    @State private var draggingID: String? = nil
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String? = nil
    @State private var swipeOffset: CGFloat = 0
    @State private var lastEdgeFlip = Date.distantPast

    @State private var folderDragID: String? = nil
    @State private var folderDragPoint: CGPoint = .zero
    @State private var folderEjecting = false
    @State private var folderCellFrames: [String: CGRect] = [:]

    private let side: CGFloat = 46
    private let gapX: CGFloat = 16
    private let gapY: CGFloat = 20
    private var topMargin: CGFloat { topInset }
    private let canvasSpace = "canvas"
    private let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    private let flow = Animation.spring(response: 0.28, dampingFraction: 0.78)

    private var C: Int { max(1, settings.columns) }
    private var R: Int { max(1, settings.rows) }
    private var perPage: Int { C * R }

    private var pageCount: Int { max(1, pages.count) }
    private var navPageCount: Int { pageCount + (draggingID != nil ? 1 : 0) }
    private var clampedPage: Int { min(max(page, 0), navPageCount - 1) }

    private var cellW: CGFloat { max(64, (size.width - 2 * side - CGFloat(C - 1) * gapX) / CGFloat(C)) }
    private var cellH: CGFloat { settings.iconSize + (settings.showLabels ? 34 : 10) }

    private var placedItems: [PlacedItem] {
        var out: [PlacedItem] = []
        for (p, items) in pages.enumerated() {
            for (i, e) in items.enumerated() { out.append(PlacedItem(page: p, index: i, entry: e)) }
        }
        return out
    }

    var body: some View {
        let cp = clampedPage

        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }

            ForEach(placedItems) { pl in
                itemView(pl.entry)
                    .frame(width: cellW, height: cellH)
                    // The dragged item stays in its page (so its gesture keeps
                    // firing) but is drawn at the cursor, on top.
                    .position(pl.entry.id == draggingID ? dragPoint : center(page: pl.page, index: pl.index, cp: cp))
                    .zIndex(pl.entry.id == draggingID ? 100 : 1)
            }

            if navPageCount > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<navPageCount, id: \.self) { i in
                        Circle().fill(.white.opacity(i == cp ? 0.95 : (i >= pageCount ? 0.18 : 0.35)))
                            .frame(width: 7, height: 7)
                            .onTapGesture { withAnimation(spring) { page = i } }
                    }
                }
                .position(x: size.width / 2, y: size.height - 14)
            }

            if let fid = model.openFolderID, let folder = currentFolder(fid) {
                folderLayer(folder)
                    .zIndex(200)   // above the grid items (which carry zIndex 1)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .coordinateSpace(name: canvasSpace)
        .onAppear { pages = buildPages() }
        .onChange(of: bus.resetTick) { _, _ in
            draggingID = nil; folderTargetID = nil; folderDragID = nil; folderEjecting = false
            swipeOffset = 0; page = 0
            pages = buildPages()
        }
        .onChange(of: model.displayEntries) { _, _ in if draggingID == nil { pages = buildPages() } }
        .onChange(of: bus.nextPageTick) { _, _ in withAnimation(spring) { page = min(cp + 1, navPageCount - 1) } }
        .onChange(of: bus.prevPageTick) { _, _ in withAnimation(spring) { page = max(cp - 1, 0) } }
        .onChange(of: bus.scrollTick) { _, _ in
            var off = swipeOffset + bus.scrollDX * 2.2
            if cp == 0 && off > 0 { off *= 0.35 }
            if cp >= navPageCount - 1 && off < 0 { off *= 0.35 }
            swipeOffset = off
        }
        .onChange(of: bus.scrollEndTick) { _, _ in
            let d = swipeOffset
            var np = cp
            if d <= -size.width * 0.1 { np = min(cp + 1, navPageCount - 1) }
            else if d >= size.width * 0.1 { np = max(cp - 1, 0) }
            withAnimation(spring) { page = np; swipeOffset = 0 }
        }
    }

    // MARK: - Page model

    private func buildPages() -> [[LaunchEntry]] {
        let visible = model.displayEntries
        var byID: [String: LaunchEntry] = [:]
        for e in visible { byID[e.id] = e }

        var result: [[LaunchEntry]] = []
        var placed = Set<String>()
        for ids in model.pageArrangement {
            var pg: [LaunchEntry] = []
            for id in ids where !placed.contains(id) {
                if let e = byID[id] { pg.append(e); placed.insert(id) }
            }
            result.append(pg)
        }
        for e in visible where !placed.contains(e.id) {
            if result.isEmpty || result[result.count - 1].count >= perPage { result.append([]) }
            result[result.count - 1].append(e); placed.insert(e.id)
        }

        // Enforce the per-page cap (e.g. after a column/row change) and drop
        // empty pages.
        var normalized: [[LaunchEntry]] = []
        for pg in result {
            var rest = pg
            while rest.count > perPage { normalized.append(Array(rest.prefix(perPage))); rest = Array(rest.dropFirst(perPage)) }
            if !rest.isEmpty { normalized.append(rest) }
        }
        return normalized.isEmpty ? [[]] : normalized
    }

    private func cascadeOverflow() {
        var p = 0
        while p < pages.count {
            while pages[p].count > perPage {
                let overflow = pages[p].removeLast()
                if p + 1 >= pages.count { pages.append([]) }
                pages[p + 1].insert(overflow, at: 0)
            }
            p += 1
        }
    }

    private func removeEmptyPages() {
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
    }

    private func locate(_ id: String) -> (Int, Int)? {
        for p in pages.indices {
            if let i = pages[p].firstIndex(where: { $0.id == id }) { return (p, i) }
        }
        return nil
    }

    // MARK: - Item view

    @ViewBuilder private func itemView(_ entry: LaunchEntry) -> some View {
        let isDrag = entry.id == draggingID
        let isTarget = folderTargetID == entry.id

        Group {
            switch entry {
            case .app(let id): AppIcon(model: model, appID: id, onLaunch: onLaunch)
            case .folder(let f): FolderIcon(model: model, folder: f)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(isTarget ? 0.22 : 0))
                .scaleEffect(isTarget ? 1.0 : 0.6)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTarget)
        )
        .scaleEffect(isDrag ? 1.16 : (isTarget ? 0.9 : 1))
        .shadow(color: .black.opacity(isDrag ? 0.4 : 0), radius: 14, y: 7)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTarget)
        .gesture(dragGesture(entry))
    }

    private func dragGesture(_ entry: LaunchEntry) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(canvasSpace))
            .onChanged { v in
                if draggingID == nil { beginDrag(entry) }
                dragPoint = v.location
                updateDrag(v.location)
            }
            .onEnded { v in endDrag(at: v.location) }
    }

    private func beginDrag(_ entry: LaunchEntry) {
        draggingID = entry.id
        pages = buildPages()
    }

    // MARK: - Geometry

    private func center(page p: Int, index i: Int, cp: Int) -> CGPoint {
        let r = i / C
        let c = i % C
        let x = (CGFloat(p) - CGFloat(cp)) * size.width + side + CGFloat(c) * (cellW + gapX) + cellW / 2 + swipeOffset
        let y = topMargin + CGFloat(r) * (cellH + gapY) + cellH / 2
        return CGPoint(x: x, y: y)
    }

    private func targetAt(_ pt: CGPoint) -> (Int, Int) {
        let p = clampedPage
        let c = min(max(Int((pt.x - side + gapX / 2) / (cellW + gapX)), 0), C - 1)
        let r = min(max(Int((pt.y - topMargin) / (cellH + gapY)), 0), R - 1)
        let slot = r * C + c
        let count = (p < pages.count) ? pages[p].count : 0
        return (p, min(slot, count))
    }

    // MARK: - Drag handling

    private func updateDrag(_ pt: CGPoint) {
        let m: CGFloat = 55
        if pt.x < m { edgeFlip(-1) } else if pt.x > size.width - m { edgeFlip(1) }

        // Folder preview: hovering the centre of an existing item.
        let (tp, ti) = targetAt(pt)
        if tp < pages.count, ti < pages[tp].count {
            let occ = pages[tp][ti]
            let ctr = center(page: tp, index: ti, cp: clampedPage)
            if abs(pt.x - ctr.x) < cellW * 0.3 && abs(pt.y - ctr.y) < cellH * 0.3 {
                folderTargetID = occ.id
                return
            }
        }
        folderTargetID = nil
    }

    private func edgeFlip(_ dir: Int) {
        guard Date().timeIntervalSince(lastEdgeFlip) > 0.55 else { return }
        let np = min(max(page + dir, 0), navPageCount - 1)
        if np != page {
            if np >= pages.count { pages.append([]) }
            withAnimation(spring) { page = np }
            lastEdgeFlip = Date()
        }
    }

    private func endDrag(at loc: CGPoint) {
        let did = draggingID
        let ft = folderTargetID
        guard let did else {
            withAnimation(flow) { draggingID = nil; folderTargetID = nil }
            return
        }
        if let ft {
            // Merge into / create a folder, keeping the folder where the target
            // sat (don't let it jump to the last page).
            let ti = model.entries.firstIndex { $0.id == ft } ?? 0
            model.combine(draggedEntryID: did, ontoIndex: ti)
            let draggedAppID = did.hasPrefix("app:") ? String(did.dropFirst(4)) : nil
            let newFolder = draggedAppID.flatMap { a in
                model.entries.first { if case .folder(let f) = $0 { return f.appIDs.contains(a) }; return false }
            }
            withAnimation(flow) {
                if let newFolder, let (tp, tpi) = locate(ft) {
                    pages[tp][tpi] = newFolder               // folder takes the target's slot
                    if let (sp, si) = locate(did) { pages[sp].remove(at: si) }
                    removeEmptyPages()
                    draggingID = nil; folderTargetID = nil
                    model.commitPages(pages)
                    return
                }
                draggingID = nil; folderTargetID = nil
                pages = buildPages()
            }
        } else if let (sp, si) = locate(did) {
            var (tp, ti) = targetAt(loc)
            withAnimation(flow) {
                let item = pages[sp].remove(at: si)   // remove only on release
                if sp == tp && si < ti { ti -= 1 }
                if tp >= pages.count { pages.append([]); tp = pages.count - 1; ti = 0 }
                ti = min(max(ti, 0), pages[tp].count)
                pages[tp].insert(item, at: ti)
                cascadeOverflow()
                removeEmptyPages()
                draggingID = nil; folderTargetID = nil
            }
            model.commitPages(pages)
        } else {
            withAnimation(flow) { draggingID = nil; folderTargetID = nil }
        }
    }

    // MARK: - In-canvas folder

    private func currentFolder(_ id: String) -> Folder? {
        for e in model.entries { if case .folder(let f) = e, f.id == id { return f } }
        return nil
    }

    @ViewBuilder private func folderLayer(_ folder: Folder) -> some View {
        let apps = model.appsInFolder(folder)
        let fIcon = min(settings.iconSize, 84)
        let fCellW = fIcon + 24
        let fCellH = fIcon + 34
        let fCols = min(5, max(1, apps.count))

        ZStack {
            Color.black.opacity(folderEjecting ? 0.12 : 0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeFolder() }
                .animation(.easeOut(duration: 0.2), value: folderEjecting)

            VStack(spacing: 20) {
                Text(folder.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fCellW), spacing: 20), count: fCols), spacing: 22) {
                    ForEach(apps, id: \.id) { app in
                        folderAppCell(app: app, folder: folder, cellW: fCellW, cellH: fCellH)
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: CGFloat(fCols) * (fCellW + 20) + 72)
            .background(
                // Fully opaque base (blocks the grid) + a thin frosted tint.
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.45), radius: 36, y: 16)
            .opacity(folderEjecting ? 0 : 1)
            .scaleEffect(folderEjecting ? 0.94 : 1)
            .animation(.easeOut(duration: 0.2), value: folderEjecting)

            if let fd = folderDragID, let app = model.app(for: fd) {
                AppIcon(model: model, appID: app.id, onLaunch: { _ in })
                    .frame(width: fCellW, height: fCellH)
                    .scaleEffect(1.16)
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    .position(folderDragPoint)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(CellFramePreference.self) { folderCellFrames = $0 }
    }

    private func folderAppCell(app: AppItem, folder: Folder, cellW: CGFloat, cellH: CGFloat) -> some View {
        AppIcon(model: model, appID: app.id, onLaunch: onLaunch)
            .frame(width: cellW, height: cellH)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: CellFramePreference.self,
                                           value: ["app:" + app.id: geo.frame(in: .named(canvasSpace))])
                }
            )
            .opacity(folderDragID == app.id ? 0.28 : 1)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named(canvasSpace))
                    .onChanged { v in
                        folderDragID = app.id
                        folderDragPoint = v.location
                        folderEjecting = !insideFolder(v.location)
                    }
                    .onEnded { v in handleFolderOut(app.id, folder: folder, at: v.location) }
            )
            .contextMenu {
                Button("打开") { onLaunch(app.id) }
                Button("移出文件夹") {
                    model.removeFromFolder(appID: app.id, folderID: folder.id)
                    if model.appsInFolder(folder).count <= 1 { closeFolder() }
                }
            }
    }

    private func insideFolder(_ p: CGPoint) -> Bool {
        folderCellFrames.values.contains { $0.insetBy(dx: -50, dy: -50).contains(p) }
    }

    private func handleFolderOut(_ appID: String, folder: Folder, at loc: CGPoint) {
        defer { folderDragID = nil; folderEjecting = false }
        let key = "app:" + appID
        if insideFolder(loc), let hit = folderCellFrames.first(where: { $0.key != key && $0.value.contains(loc) }) {
            let targetAppID = String(hit.key.dropFirst(4))
            guard let from = folder.appIDs.firstIndex(of: appID),
                  let to = folder.appIDs.firstIndex(of: targetAppID) else { return }
            let relX = (loc.x - hit.value.minX) / max(hit.value.width, 1)
            model.reorderInFolder(folder.id, from: from, to: relX >= 0.5 ? to + 1 : to)
        } else if !insideFolder(loc) {
            // Ejected onto the grid: drop into the released page/slot.
            model.removeFromFolder(appID: appID, folderID: folder.id)
            pages = buildPages()
            let (tp, ti) = targetAt(loc)
            if let (sp, si) = locate(key), tp < pages.count {
                let item = pages[sp].remove(at: si)
                var t = ti
                if sp == tp && si < t { t -= 1 }
                t = min(max(t, 0), pages[tp].count)
                pages[tp].insert(item, at: t)
                cascadeOverflow()
            }
            removeEmptyPages()
            model.commitPages(pages)
            closeFolder()
        }
    }

    private func closeFolder() {
        withAnimation(spring) { model.openFolderID = nil }
    }
}
