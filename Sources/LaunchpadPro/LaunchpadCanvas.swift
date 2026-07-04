import SwiftUI
import AppKit

/// A single flat, absolutely-positioned launcher canvas with live reordering:
/// every item is placed by its index, so when the dragged item moves, the
/// others animate to fill the gap (like the native Launchpad). Pages are laid
/// out horizontally; folder creation and cross-page moves are all derived from
/// the cursor position.
struct LaunchpadCanvas: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var bus = LauncherBus.shared
    let size: CGSize
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    @State private var order: [LaunchEntry] = []
    @State private var page = 0
    @State private var draggingID: String? = nil
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String? = nil
    @State private var swipeOffset: CGFloat = 0
    @State private var lastEdgeFlip = Date.distantPast

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

    /// While dragging we render/mutate a local copy; otherwise the model's list.
    private var live: [LaunchEntry] { draggingID != nil ? order : model.displayEntries }
    private var pageCount: Int { max(1, Int(ceil(Double(live.count) / Double(perPage)))) }
    private var clampedPage: Int { min(max(page, 0), pageCount - 1) }

    private var cellW: CGFloat { max(64, (size.width - 2 * side - CGFloat(C - 1) * gapX) / CGFloat(C)) }
    private var cellH: CGFloat { settings.iconSize + (settings.showLabels ? 34 : 10) }

    var body: some View {
        let items = live
        let cp = clampedPage

        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }

            ForEach(items) { entry in
                let idx = items.firstIndex { $0.id == entry.id } ?? 0
                itemView(entry)
                    .frame(width: cellW, height: cellH)
                    .position(entry.id == draggingID ? dragPoint : center(idx, page: cp))
                    .zIndex(entry.id == draggingID ? 100 : 1)
            }

            if pageCount > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle().fill(.white.opacity(i == cp ? 0.95 : 0.35))
                            .frame(width: 7, height: 7)
                            .onTapGesture { withAnimation(spring) { page = i } }
                    }
                }
                .position(x: size.width / 2, y: size.height - 14)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .coordinateSpace(name: canvasSpace)
        .onChange(of: bus.nextPageTick) { _, _ in withAnimation(spring) { page = min(cp + 1, pageCount - 1) } }
        .onChange(of: bus.prevPageTick) { _, _ in withAnimation(spring) { page = max(cp - 1, 0) } }
        .onChange(of: bus.scrollTick) { _, _ in
            var off = swipeOffset + bus.scrollDX * 2.2
            if cp == 0 && off > 0 { off *= 0.35 }
            if cp >= pageCount - 1 && off < 0 { off *= 0.35 }
            swipeOffset = off
        }
        .onChange(of: bus.scrollEndTick) { _, _ in
            let d = swipeOffset
            var np = cp
            if d <= -size.width * 0.1 { np = min(cp + 1, pageCount - 1) }
            else if d >= size.width * 0.1 { np = max(cp - 1, 0) }
            withAnimation(spring) { page = np; swipeOffset = 0 }
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
                if draggingID == nil {
                    draggingID = entry.id
                    order = model.displayEntries
                }
                dragPoint = v.location
                updateDrag(v.location)
            }
            .onEnded { v in endDrag() }
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

    private func slotIndex(at pt: CGPoint) -> Int {
        let c = min(max(Int((pt.x - side + gapX / 2) / (cellW + gapX)), 0), C - 1)
        let r = min(max(Int((pt.y - topMargin) / (cellH + gapY)), 0), R - 1)
        let idx = clampedPage * perPage + r * C + c
        return min(max(idx, 0), max(0, order.count - 1))
    }

    // MARK: - Drag handling

    private func updateDrag(_ pt: CGPoint) {
        // Cross-page: hold near an edge to flip.
        let m: CGFloat = 55
        if pt.x < m { edgeFlip(-1) } else if pt.x > size.width - m { edgeFlip(1) }

        guard let from = order.firstIndex(where: { $0.id == draggingID }) else { return }
        let target = slotIndex(at: pt)

        // Folder zone: near the centre of another occupied slot.
        if target < order.count, order[target].id != draggingID {
            let ctr = center(target, page: clampedPage)
            if abs(pt.x - ctr.x) < cellW * 0.3 && abs(pt.y - ctr.y) < cellH * 0.3 {
                folderTargetID = order[target].id
                return
            }
        }
        folderTargetID = nil
        if target != from { moveDragged(from: from, to: target) }
    }

    private func moveDragged(from: Int, to: Int) {
        let dest = min(max(to > from ? to - 1 : to, 0), order.count - 1)
        if dest == from { return }
        withAnimation(flow) {
            let item = order.remove(at: from)
            order.insert(item, at: min(max(dest, 0), order.count))
        }
    }

    private func edgeFlip(_ dir: Int) {
        guard Date().timeIntervalSince(lastEdgeFlip) > 0.55 else { return }
        let np = min(max(page + dir, 0), pageCount - 1)
        if np != page {
            withAnimation(spring) { page = np }
            lastEdgeFlip = Date()
        }
    }

    private func endDrag() {
        defer {
            withAnimation(flow) { draggingID = nil; folderTargetID = nil }
        }
        guard let did = draggingID else { return }
        if let ft = folderTargetID {
            let ti = model.entries.firstIndex { $0.id == ft } ?? 0
            model.combine(draggedEntryID: did, ontoIndex: ti)
        } else {
            model.setDisplayOrder(order)
        }
    }
}
