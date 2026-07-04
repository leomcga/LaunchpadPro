import SwiftUI
import AppKit

/// A flat, absolutely-positioned launcher canvas with a gap-aware slot layout.
/// Items live in fixed slots (nil = empty), so pages can be partially filled and
/// an app stays exactly where it's placed — no forced repacking. Dragging pushes
/// neighbours into the nearest empty slot (like the native Launchpad) and can
/// create/collapse trailing pages.
struct LaunchpadCanvas: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var bus = LauncherBus.shared
    let size: CGSize
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    @State private var slots: [LaunchEntry?] = []
    @State private var page = 0
    @State private var draggingID: String? = nil
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String? = nil
    @State private var swipeOffset: CGFloat = 0
    @State private var lastEdgeFlip = Date.distantPast

    // Open-folder state (shares the canvas coordinate space).
    @State private var folderDragID: String? = nil
    @State private var folderDragPoint: CGPoint = .zero
    @State private var folderEjecting = false
    @State private var folderCellFrames: [String: CGRect] = [:]

    private let side: CGFloat = 46
    private let gapX: CGFloat = 16
    private let gapY: CGFloat = 20
    private let topMargin: CGFloat = 8
    private let canvasSpace = "canvas"
    private let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    private let flow = Animation.spring(response: 0.28, dampingFraction: 0.78)

    private var C: Int { max(1, settings.columns) }
    private var R: Int { max(1, settings.rows) }
    private var perPage: Int { C * R }

    private var pageCount: Int { max(1, Int(ceil(Double(slots.count) / Double(perPage)))) }
    private var navPageCount: Int { pageCount + (draggingID != nil ? 1 : 0) }
    private var clampedPage: Int { min(max(page, 0), navPageCount - 1) }

    private var cellW: CGFloat { max(64, (size.width - 2 * side - CGFloat(C - 1) * gapX) / CGFloat(C)) }
    private var cellH: CGFloat { settings.iconSize + (settings.showLabels ? 34 : 10) }

    var body: some View {
        let cp = clampedPage

        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }

            ForEach(slots.compactMap { $0 }, id: \.id) { entry in
                let idx = slots.firstIndex { $0?.id == entry.id } ?? 0
                itemView(entry)
                    .frame(width: cellW, height: cellH)
                    .position(entry.id == draggingID ? dragPoint : center(idx, page: cp))
                    .zIndex(entry.id == draggingID ? 100 : 1)
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
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .coordinateSpace(name: canvasSpace)
        .onAppear { slots = buildSlots() }
        .onChange(of: model.displayEntries) { _, _ in if draggingID == nil { slots = buildSlots() } }
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

    // MARK: - Slot model

    private func buildSlots() -> [LaunchEntry?] {
        let visible = model.displayEntries
        var byID: [String: LaunchEntry] = [:]
        for e in visible { byID[e.id] = e }

        var result: [LaunchEntry?] = []
        var placed = Set<String>()
        for id in model.slotArrangement {
            if let id, let e = byID[id], !placed.contains(id) {
                result.append(e); placed.insert(id)
            } else {
                result.append(nil)
            }
        }
        for e in visible where !placed.contains(e.id) {
            if let gap = result.firstIndex(where: { $0 == nil }) { result[gap] = e }
            else { result.append(e) }
            placed.insert(e.id)
        }
        while let last = result.last, last == nil { result.removeLast() }
        return result
    }

    private func normalizeSlots() {
        while let last = slots.last, last == nil { slots.removeLast() }
    }

    private func ensureCapacity(page p: Int) {
        let need = (p + 1) * perPage
        if slots.count < need {
            slots.append(contentsOf: Array(repeating: nil, count: need - slots.count))
        }
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
                if draggingID == nil { draggingID = entry.id; slots = buildSlots() }
                dragPoint = v.location
                updateDrag(v.location)
            }
            .onEnded { _ in endDrag() }
    }

    // MARK: - Geometry

    private func center(_ i: Int, page: Int) -> CGPoint {
        let p = i / perPage
        let inp = i % perPage
        let r = inp / C
        let c = inp % C
        let x = (CGFloat(p) - CGFloat(page)) * size.width + side + CGFloat(c) * (cellW + gapX) + cellW / 2 + swipeOffset
        let y = topMargin + CGFloat(r) * (cellH + gapY) + cellH / 2
        return CGPoint(x: x, y: y)
    }

    private func slotAtPoint(_ pt: CGPoint) -> Int {
        let c = min(max(Int((pt.x - side + gapX / 2) / (cellW + gapX)), 0), C - 1)
        let r = min(max(Int((pt.y - topMargin) / (cellH + gapY)), 0), R - 1)
        let idx = clampedPage * perPage + r * C + c
        return min(max(idx, 0), max(0, slots.count - 1))
    }

    // MARK: - Drag handling

    private func updateDrag(_ pt: CGPoint) {
        let m: CGFloat = 55
        if pt.x < m { edgeFlip(-1) } else if pt.x > size.width - m { edgeFlip(1) }

        ensureCapacity(page: clampedPage)
        let t = slotAtPoint(pt)

        if t < slots.count, let occ = slots[t], occ.id != draggingID {
            let ctr = center(t, page: clampedPage)
            if abs(pt.x - ctr.x) < cellW * 0.3 && abs(pt.y - ctr.y) < cellH * 0.3 {
                folderTargetID = occ.id
                return
            }
        }
        folderTargetID = nil
        moveDraggedToSlot(t)
    }

    private func moveDraggedToSlot(_ t: Int) {
        guard let from = slots.firstIndex(where: { $0?.id == draggingID }) else { return }
        if t == from { return }
        withAnimation(flow) {
            let item = slots[from]
            slots[from] = nil
            if t < slots.count, slots[t] == nil {
                slots[t] = item
            } else {
                insertShift(item, at: t)
            }
        }
    }

    /// Open slot `t` by pushing the run of items between `t` and the nearest
    /// empty slot one step toward that empty slot, then drop `item` at `t`.
    private func insertShift(_ item: LaunchEntry?, at t: Int) {
        if t >= slots.count {
            slots.append(contentsOf: Array(repeating: nil, count: t - slots.count + 1))
        }
        if slots[t] == nil { slots[t] = item; return }

        var e = -1, best = Int.max
        for i in slots.indices where slots[i] == nil {
            let d = abs(i - t); if d < best { best = d; e = i }
        }
        if e == -1 { slots.append(item); return }
        if e > t {
            var i = e
            while i > t { slots[i] = slots[i - 1]; i -= 1 }
        } else {
            var i = e
            while i < t { slots[i] = slots[i + 1]; i += 1 }
        }
        slots[t] = item
    }

    private func edgeFlip(_ dir: Int) {
        guard Date().timeIntervalSince(lastEdgeFlip) > 0.55 else { return }
        let np = min(max(page + dir, 0), navPageCount - 1)
        if np != page {
            if np >= pageCount { ensureCapacity(page: np) }
            withAnimation(spring) { page = np }
            lastEdgeFlip = Date()
        }
    }

    private func endDrag() {
        let did = draggingID
        let ft = folderTargetID
        withAnimation(flow) { draggingID = nil; folderTargetID = nil }
        guard let did else { return }
        if let ft {
            let ti = model.entries.firstIndex { $0.id == ft } ?? 0
            model.combine(draggedEntryID: did, ontoIndex: ti)
            slots = buildSlots()
        } else {
            normalizeSlots()
            model.commitSlots(slots)
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
            Color.black.opacity(folderEjecting ? 0.1 : 0.42)
                .contentShape(Rectangle())
                .onTapGesture { closeFolder() }
                .animation(.easeOut(duration: 0.2), value: folderEjecting)

            VStack(spacing: 16) {
                Text(folder.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fCellW), spacing: 18), count: fCols), spacing: 18) {
                    ForEach(apps, id: \.id) { app in
                        folderAppCell(app: app, folder: folder, cellW: fCellW, cellH: fCellH)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: CGFloat(5) * (fCellW + 18) + 64)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
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
            // Ejected onto the grid: place at the released slot.
            model.removeFromFolder(appID: appID, folderID: folder.id)
            slots = buildSlots()
            ensureCapacity(page: clampedPage)
            let t = slotAtPoint(loc)
            if let from = slots.firstIndex(where: { $0?.id == key }) {
                let item = slots[from]
                slots[from] = nil
                if t < slots.count, slots[t] == nil { slots[t] = item } else { insertShift(item, at: t) }
            }
            normalizeSlots()
            model.commitSlots(slots)
            closeFolder()
        }
    }

    private func closeFolder() {
        withAnimation(spring) { model.openFolderID = nil }
    }
}
