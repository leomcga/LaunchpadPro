import SwiftUI

private struct PlacedEntry: Identifiable {
    let page: Int
    let index: Int
    let entry: LaunchEntry

    var id: String { entry.id }
}

private struct EntryFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct FolderPanelMetrics {
    let cell: CGSize
    let columns: Int
    let rows: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let panelWidth: CGFloat
    let naturalPanelHeight: CGFloat
    let visiblePanelHeight: CGFloat

    var needsScroll: Bool {
        naturalPanelHeight > visiblePanelHeight + 0.5
    }
}

struct PagedLauncherView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var bus = LauncherBus.shared

    let size: CGSize
    let topInset: CGFloat
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void

    @State private var pages: [[LaunchEntry]] = []
    @State private var previewPages: [[LaunchEntry]]?
    @State private var currentPage = 0
    @State private var draggingID: String?
    @State private var dragPoint: CGPoint = .zero
    @State private var folderTargetID: String?
    @State private var lastPreviewKey: String?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeTargetOffset: CGFloat = 0
    @State private var lastEdgeFlip = Date.distantPast
    @State private var entryFrames: [String: CGRect] = [:]

    @State private var presentedFolderID: String?
    @State private var folderReveal: CGFloat = 0
    @State private var folderSourceFrame: CGRect?
    @State private var folderDragID: String?
    @State private var folderDragPoint: CGPoint = .zero
    @State private var folderEjecting = false
    @State private var closingFromFolderEject = false
    @State private var lastFolderEjectPreviewKey: String?
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var titleDraft = ""
    @State private var editingFolderTitle = false
    @FocusState private var folderTitleFocused: Bool

    private let sidePadding: CGFloat = 52
    private let columnGap: CGFloat = 16
    private let rowGap: CGFloat = 20
    private let canvasSpace = "paged-launcher"
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.84)
    private let flow = Animation.spring(response: 0.24, dampingFraction: 0.80)
    private let snap = Animation.interpolatingSpring(mass: 0.82, stiffness: 260, damping: 34, initialVelocity: 0)
    private let folderOpenAnimation = Animation.interpolatingSpring(mass: 0.82, stiffness: 250, damping: 28, initialVelocity: 0.14)
    private let folderCloseAnimation = Animation.interpolatingSpring(mass: 0.90, stiffness: 330, damping: 34, initialVelocity: 0)

    private var columns: Int { max(1, settings.columns) }
    private var rows: Int { max(1, settings.rows) }
    private var perPage: Int { max(1, columns * rows) }
    private var cellWidth: CGFloat {
        max(68, (size.width - 2 * sidePadding - CGFloat(columns - 1) * columnGap) / CGFloat(columns))
    }
    private var cellHeight: CGFloat {
        settings.iconSize + (settings.showLabels ? 36 : 10)
    }
    private var activePages: [[LaunchEntry]] { previewPages ?? pages }
    private var pageCount: Int { max(1, activePages.count) }
    private var navigablePageCount: Int {
        max(pageCount, pages.count + (draggingID == nil ? 0 : 1), 1)
    }
    private var clampedPage: Int {
        min(max(currentPage, 0), navigablePageCount - 1)
    }

    private var placedEntries: [PlacedEntry] {
        pages.enumerated().flatMap { pageIndex, entries in
            entries.enumerated().map { itemIndex, entry in
                PlacedEntry(page: pageIndex, index: itemIndex, entry: entry)
            }
        }
    }

    var body: some View {
        let page = clampedPage
        let indexMap = indexMap(for: activePages)
        let folderProgress = effectiveFolderReveal

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            ZStack(alignment: .topLeading) {
                ForEach(placedEntries) { placed in
                    entryView(placed.entry)
                        .frame(width: cellWidth, height: cellHeight)
                        .position(position(for: placed, selectedPage: page, indexMap: indexMap))
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: EntryFramePreference.self,
                                    value: [placed.entry.id: proxy.frame(in: .named(canvasSpace))]
                                )
                            }
                        )
                        .zIndex(1)
                }
            }
            .offset(x: swipeOffset)
            .compositingGroup()
            .blur(radius: 18 * folderProgress)
            .saturation(Double(1 - 0.28 * folderProgress))
            .brightness(Double(-0.16 * folderProgress))
            .opacity(Double(1 - 0.58 * folderProgress))
            .animation(.easeInOut(duration: 0.20), value: folderProgress)

            if let draggingID, let dragged = entry(with: draggingID, in: pages) {
                floatingEntryView(dragged)
                    .frame(width: cellWidth, height: cellHeight)
                    .position(dragPoint)
                    .zIndex(100)
                    .allowsHitTesting(false)
                    .blur(radius: 18 * folderProgress)
                    .opacity(Double(1 - 0.65 * folderProgress))
            }

            if navigablePageCount > 1 {
                pageDots(selectedPage: page)
                    .position(x: size.width / 2, y: size.height - 16)
                    .zIndex(10)
                    .blur(radius: 8 * folderProgress)
                    .opacity(Double(1 - 0.82 * folderProgress))
                    .animation(.easeInOut(duration: 0.18), value: folderProgress)
            }

            if let folderID = presentedFolderID,
               let folder = currentFolder(folderID) {
                folderLayer(folder)
                    .zIndex(200)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .coordinateSpace(name: canvasSpace)
        .onPreferenceChange(EntryFramePreference.self) { entryFrames = $0 }
        .onAppear {
            pages = buildPages()
            previewPages = nil
            currentPage = min(currentPage, max(0, pages.count - 1))
        }
        .onChange(of: model.displayEntries) { _, _ in
            guard draggingID == nil else { return }
            pages = buildPages()
            previewPages = nil
            currentPage = min(currentPage, max(0, pages.count - 1))
        }
        .onChange(of: settings.columns) { _, _ in rebuildForGridChange() }
        .onChange(of: settings.rows) { _, _ in rebuildForGridChange() }
        .onChange(of: bus.resetTick) { _, _ in
            cancelDrag()
            resetSwipe()
            currentPage = 0
            pages = buildPages()
        }
        .onChange(of: bus.nextPageTick) { _, _ in
            withAnimation(spring) { currentPage = min(clampedPage + 1, navigablePageCount - 1) }
        }
        .onChange(of: bus.previousPageTick) { _, _ in
            withAnimation(spring) { currentPage = max(clampedPage - 1, 0) }
        }
        .onChange(of: bus.liveScrollTick) { _, _ in
            let next = constrainedSwipeOffset(swipeTargetOffset + bus.latestScrollDX * 1.14)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                swipeTargetOffset = next
                if abs(swipeOffset - next) > size.width * 0.18 {
                    swipeOffset = next
                }
            }
        }
        .onChange(of: bus.displayFrameTick) { _, _ in
            guard model.openFolderID == nil, presentedFolderID == nil else { return }
            guard abs(swipeOffset - swipeTargetOffset) > 0.35 else {
                swipeOffset = swipeTargetOffset
                return
            }
            let dt = max(1.0 / 240.0, min(bus.displayFrameDuration, 1.0 / 30.0))
            let blend = CGFloat(min(0.72, max(0.26, 1 - exp(-76 * dt))))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                swipeOffset += (swipeTargetOffset - swipeOffset) * blend
            }
        }
        .onChange(of: bus.endScrollTick) { _, _ in
            let distanceThreshold = size.width * 0.13
            let velocityThreshold: CGFloat = 3.4
            let energyThreshold: CGFloat = 18
            let settledOffset = abs(swipeTargetOffset) > abs(swipeOffset) ? swipeTargetOffset : swipeOffset
            var page = clampedPage
            let shouldAdvance = settledOffset <= -distanceThreshold
                || bus.swipeVelocity <= -velocityThreshold
                || bus.swipeEnergy <= -energyThreshold
            let shouldGoBack = settledOffset >= distanceThreshold
                || bus.swipeVelocity >= velocityThreshold
                || bus.swipeEnergy >= energyThreshold
            if shouldAdvance { page = min(page + 1, navigablePageCount - 1) }
            if shouldGoBack { page = max(page - 1, 0) }
            withAnimation(snap) {
                currentPage = page
                swipeTargetOffset = 0
                swipeOffset = 0
            }
        }
        .onChange(of: model.openFolderID) { _, newValue in
            if let newValue {
                presentFolder(newValue)
            } else {
                dismissPresentedFolder()
            }
            cancelDrag()
        }
    }

    @ViewBuilder private func entryView(_ entry: LaunchEntry) -> some View {
        let isDragging = entry.id == draggingID
        let isFolderTarget = entry.id == folderTargetID

        let base = LauncherEntryView(
            model: model,
            entry: entry,
            cell: CGSize(width: cellWidth, height: cellHeight),
            isDragging: isDragging,
            isFolderTarget: isFolderTarget,
            onLaunch: onLaunch
        )

        if model.openFolderID == nil, presentedFolderID == nil {
            base.highPriorityGesture(dragGesture(entry))
        } else {
            base
        }
    }

    private func floatingEntryView(_ entry: LaunchEntry) -> some View {
        LauncherEntryView(
            model: model,
            entry: entry,
            cell: CGSize(width: cellWidth, height: cellHeight),
            isDragging: false,
            isFolderTarget: false,
            onLaunch: { _ in }
        )
        .scaleEffect(1.13)
        .shadow(color: .black.opacity(0.42), radius: 16, y: 8)
    }

    private func dragGesture(_ entry: LaunchEntry) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(canvasSpace))
            .onChanged { value in
                if draggingID == nil {
                    beginDrag(entry, at: value.location)
                }
                dragPoint = value.location
                updateDrag(at: value.location)
            }
            .onEnded { value in
                finishDrag(at: value.location)
            }
    }

    private func beginDrag(_ entry: LaunchEntry, at point: CGPoint) {
        guard model.openFolderID == nil, presentedFolderID == nil else { return }
        pages = buildPages()
        previewPages = nil
        draggingID = entry.id
        dragPoint = point
    }

    private func updateDrag(at point: CGPoint) {
        guard let draggingID else { return }

        let edgeMargin: CGFloat = 54
        if point.x < edgeMargin {
            flipPage(direction: -1)
        } else if point.x > size.width - edgeMargin {
            flipPage(direction: 1)
        }

        if let target = mergeTarget(at: point, excluding: draggingID),
           canMerge(draggingID: draggingID, target: target) {
            if folderTargetID != target.id {
                folderTargetID = target.id
                lastPreviewKey = nil
            }
            return
        } else {
            folderTargetID = nil
        }

        let target = reorderSlot(for: point, draggingID: draggingID)
        let key = "\(target.page):\(target.index)"
        guard key != lastPreviewKey else { return }
        lastPreviewKey = key

        withAnimation(flow) {
            previewPages = reorderedPreview(draggingID: draggingID, target: target)
        }
    }

    private func finishDrag(at point: CGPoint) {
        guard let draggingID else {
            cancelDrag()
            return
        }

        let dropTargetID = folderTargetID ?? mergeTarget(at: point, excluding: draggingID)?.id
        if let dropTargetID, commitMergeToModel(draggingID: draggingID, targetID: dropTargetID) {
            withAnimation(flow) {
                pages = buildPages()
                previewPages = nil
                self.draggingID = nil
                self.folderTargetID = nil
                self.lastPreviewKey = nil
            }
            return
        }

        let target = reorderSlot(for: point, draggingID: draggingID)
        let committed = clean(previewPages ?? reorderedPreview(draggingID: draggingID, target: target))
        withAnimation(flow) {
            pages = committed
            previewPages = nil
            self.draggingID = nil
            self.folderTargetID = nil
            self.lastPreviewKey = nil
        }
        model.commitPages(committed)
    }

    private func cancelDrag() {
        draggingID = nil
        folderTargetID = nil
        previewPages = nil
        lastPreviewKey = nil
    }

    private func resetSwipe() {
        swipeOffset = 0
        swipeTargetOffset = 0
    }

    private var clampedFolderReveal: CGFloat {
        guard presentedFolderID != nil else { return 0 }
        return min(max(folderReveal, 0), 1)
    }

    private var effectiveFolderReveal: CGFloat {
        (folderEjecting || closingFromFolderEject) ? 0 : clampedFolderReveal
    }

    private func presentFolder(_ folderID: String) {
        folderDragID = nil
        folderEjecting = false
        closingFromFolderEject = false
        lastFolderEjectPreviewKey = nil
        editingFolderTitle = false
        folderSourceFrame = sourceFrame(forFolderID: folderID)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentedFolderID = folderID
            folderReveal = 0
        }

        DispatchQueue.main.async {
            guard presentedFolderID == folderID, model.openFolderID == folderID else { return }
            withAnimation(folderOpenAnimation) {
                folderReveal = 1
            }
        }
    }

    private func dismissPresentedFolder() {
        let closeFromEject = folderEjecting || closingFromFolderEject
        folderDragID = nil
        lastFolderEjectPreviewKey = nil
        editingFolderTitle = false

        guard let closingID = presentedFolderID else {
            folderEjecting = false
            closingFromFolderEject = false
            folderReveal = 0
            folderSourceFrame = nil
            return
        }

        if closeFromEject {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                folderReveal = 0
            }
        } else {
            folderEjecting = false
            withAnimation(folderCloseAnimation) {
                folderReveal = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (closeFromEject ? 0.18 : 0.34)) {
            guard model.openFolderID == nil, presentedFolderID == closingID else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentedFolderID = nil
                folderSourceFrame = nil
                folderReveal = 0
                folderEjecting = false
                closingFromFolderEject = false
                folderFrames = [:]
            }
        }
    }

    private func sourceFrame(forFolderID folderID: String) -> CGRect {
        let entryID = "folder:" + folderID
        if let frame = entryFrames[entryID],
           !frame.isNull,
           frame.width > 0,
           frame.height > 0,
           frame.width <= cellWidth * 1.8,
           frame.height <= cellHeight * 1.8 {
            return frame
        }
        if let located = locate(entryID, in: pages) {
            let center = center(page: located.page, index: located.index, selectedPage: clampedPage)
            return CGRect(
                x: center.x + swipeOffset - cellWidth / 2,
                y: center.y - cellHeight / 2,
                width: cellWidth,
                height: cellHeight
            )
        }
        return CGRect(x: size.width / 2 - 40, y: size.height / 2 - 40, width: 80, height: 80)
    }

    private func constrainedSwipeOffset(_ rawOffset: CGFloat) -> CGFloat {
        let limit = max(96, size.width * 0.30)
        if clampedPage == 0 && rawOffset > 0 {
            return rubberBand(rawOffset, limit: limit)
        }
        if clampedPage >= navigablePageCount - 1 && rawOffset < 0 {
            return -rubberBand(-rawOffset, limit: limit)
        }
        return rawOffset
    }

    private func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        guard offset > 0, limit > 0 else { return 0 }
        return (limit * offset) / (limit + offset)
    }

    private func flipPage(direction: Int) {
        guard Date().timeIntervalSince(lastEdgeFlip) > 0.55 else { return }
        let next = min(max(clampedPage + direction, 0), navigablePageCount - 1)
        guard next != currentPage else { return }
        if next >= pages.count {
            var expanded = previewPages ?? pages
            while next >= expanded.count { expanded.append([]) }
            previewPages = expanded
        }
        withAnimation(spring) { currentPage = next }
        lastEdgeFlip = Date()
    }

    private func position(
        for placed: PlacedEntry,
        selectedPage: Int,
        indexMap: [String: (page: Int, index: Int)]
    ) -> CGPoint {
        if placed.entry.id == draggingID {
            return center(page: placed.page, index: placed.index, selectedPage: selectedPage)
        }

        if let located = indexMap[placed.entry.id] {
            return center(page: located.page, index: located.index, selectedPage: selectedPage)
        }

        return center(page: placed.page, index: placed.index, selectedPage: selectedPage)
    }

    private func indexMap(for layout: [[LaunchEntry]]) -> [String: (page: Int, index: Int)] {
        var map: [String: (page: Int, index: Int)] = [:]
        map.reserveCapacity(layout.reduce(0) { $0 + $1.count })
        for pageIndex in layout.indices {
            for entryIndex in layout[pageIndex].indices {
                map[layout[pageIndex][entryIndex].id] = (pageIndex, entryIndex)
            }
        }
        return map
    }

    private func center(page: Int, index: Int, selectedPage: Int) -> CGPoint {
        let row = index / columns
        let column = index % columns
        let pageOffset = (CGFloat(page) - CGFloat(selectedPage)) * size.width
        let x = pageOffset + sidePadding + CGFloat(column) * (cellWidth + columnGap) + cellWidth / 2
        let y = topInset + CGFloat(row) * (cellHeight + rowGap) + cellHeight / 2
        return CGPoint(x: x, y: y)
    }

    private func targetSlot(for point: CGPoint) -> (page: Int, index: Int) {
        let page = clampedPage
        let column = min(max(Int((point.x - sidePadding + columnGap / 2) / (cellWidth + columnGap)), 0), columns - 1)
        let row = min(max(Int((point.y - topInset) / (cellHeight + rowGap)), 0), rows - 1)
        let slot = row * columns + column
        let count = page < activePages.count ? activePages[page].count : 0
        return (page, min(slot, count))
    }

    private func reorderSlot(for point: CGPoint, draggingID: String) -> (page: Int, index: Int) {
        let page = clampedPage
        var layout = pages
        _ = removeEntry(draggingID, from: &layout)
        while page >= layout.count { layout.append([]) }

        let count = min(layout[page].count, perPage)
        guard count > 0 else {
            return (page, 0)
        }

        for index in 0..<count {
            let center = center(page: page, index: index, selectedPage: clampedPage)
            let row = index / columns
            let column = index % columns
            let isBefore = row == (min(max(Int((point.y - topInset) / (cellHeight + rowGap)), 0), rows - 1))
                ? point.x < center.x
                : point.y < center.y
            if isBefore {
                return (page, index)
            }

            if column == columns - 1 && point.y < center.y + (cellHeight + rowGap) / 2 {
                return (page, index + 1)
            }
        }

        return (page, count)
    }

    private func mergeTarget(at point: CGPoint, excluding id: String) -> LaunchEntry? {
        // Folder creation follows the same layout used for visible icon positions.
        // When reorder preview makes icons "yield", their merge hit zones move too.
        let layout = activePages
        for pageIndex in layout.indices {
            for entryIndex in layout[pageIndex].indices {
                let entry = layout[pageIndex][entryIndex]
                guard entry.id != id else { continue }
                let center = center(page: pageIndex, index: entryIndex, selectedPage: clampedPage)
                let hitSize = settings.iconSize * 0.80
                let iconCenterY = center.y - (settings.showLabels ? 12 : 0)
                let hitRect = CGRect(
                    x: center.x - hitSize / 2,
                    y: iconCenterY - hitSize / 2,
                    width: hitSize,
                    height: hitSize
                )
                if hitRect.contains(point) {
                    return entry
                }
            }
        }
        return nil
    }

    private func canMerge(draggingID: String, target: LaunchEntry) -> Bool {
        guard let dragging = entry(with: draggingID, in: pages),
              case .app = dragging else { return false }
        switch target {
        case .app:
            return true
        case .folder:
            return true
        }
    }

    private func commitMergeToModel(draggingID: String, targetID: String) -> Bool {
        guard let draggedAppID = appID(from: draggingID), draggedAppID != appID(from: targetID) else {
            return false
        }

        if let targetAppID = appID(from: targetID) {
            return model.createFolder(appID: draggedAppID, with: targetAppID)
        }

        if let targetFolderID = folderID(from: targetID) {
            return model.addApp(draggedAppID, toFolder: targetFolderID)
        }

        return false
    }

    private func appID(from entryID: String) -> String? {
        guard entryID.hasPrefix("app:") else { return nil }
        return String(entryID.dropFirst(4))
    }

    private func folderID(from entryID: String) -> String? {
        guard entryID.hasPrefix("folder:") else { return nil }
        return String(entryID.dropFirst(7))
    }

    private func reorderedPreview(draggingID: String, target: (page: Int, index: Int)) -> [[LaunchEntry]] {
        var result = pages
        guard let source = removeEntry(draggingID, from: &result) else { return result }

        var target = target
        while target.page >= result.count { result.append([]) }
        target.index = min(max(target.index, 0), result[target.page].count)
        result[target.page].insert(source, at: target.index)
        cascadeOverflow(&result)
        return result
    }

    private func mergedPages(draggingID: String, targetID: String) -> [[LaunchEntry]]? {
        var result = pages
        guard let dragged = removeEntry(draggingID, from: &result),
              case .app(let draggedAppID) = dragged,
              let target = locate(targetID, in: result) else { return nil }

        let targetEntry = result[target.page][target.index]
        switch targetEntry {
        case .app(let targetAppID):
            result[target.page][target.index] = .folder(
                FolderRecord(name: "未命名", appIDs: [targetAppID, draggedAppID])
            )
        case .folder(var folder):
            if !folder.appIDs.contains(draggedAppID) {
                folder.appIDs.append(draggedAppID)
            }
            result[target.page][target.index] = .folder(folder)
        }

        return result
    }

    private func removeEntry(_ id: String, from pages: inout [[LaunchEntry]]) -> LaunchEntry? {
        for pageIndex in pages.indices {
            if let entryIndex = pages[pageIndex].firstIndex(where: { $0.id == id }) {
                return pages[pageIndex].remove(at: entryIndex)
            }
        }
        return nil
    }

    private func locate(_ id: String, in layout: [[LaunchEntry]]) -> (page: Int, index: Int)? {
        for pageIndex in layout.indices {
            if let entryIndex = layout[pageIndex].firstIndex(where: { $0.id == id }) {
                return (pageIndex, entryIndex)
            }
        }
        return nil
    }

    private func entry(with id: String, in layout: [[LaunchEntry]]) -> LaunchEntry? {
        guard let located = locate(id, in: layout) else { return nil }
        return layout[located.page][located.index]
    }

    private func cascadeOverflow(_ layout: inout [[LaunchEntry]]) {
        var page = 0
        while page < layout.count {
            while layout[page].count > perPage {
                let overflow = layout[page].removeLast()
                if page + 1 >= layout.count { layout.append([]) }
                layout[page + 1].insert(overflow, at: 0)
            }
            page += 1
        }
    }

    private func clean(_ layout: [[LaunchEntry]]) -> [[LaunchEntry]] {
        var result = layout.filter { !$0.isEmpty }
        if result.isEmpty { result = [[]] }
        cascadeOverflow(&result)
        return result
    }

    private func buildPages() -> [[LaunchEntry]] {
        let visible = model.displayEntries
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var used = Set<String>()
        var result: [[LaunchEntry]] = []

        for ids in model.pageArrangement {
            var page: [LaunchEntry] = []
            for id in ids where !used.contains(id) {
                if let entry = byID[id] {
                    page.append(entry)
                    used.insert(id)
                }
            }
            if !page.isEmpty {
                result.append(page)
            }
        }

        for entry in visible where !used.contains(entry.id) {
            if result.isEmpty || result[result.count - 1].count >= perPage {
                result.append([])
            }
            result[result.count - 1].append(entry)
            used.insert(entry.id)
        }

        return clean(result)
    }

    private func rebuildForGridChange() {
        guard draggingID == nil else { return }
        pages = buildPages()
        previewPages = nil
        currentPage = min(currentPage, max(0, pages.count - 1))
    }

    private func pageDots(selectedPage: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<navigablePageCount, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == selectedPage ? 0.94 : (index >= pageCount ? 0.18 : 0.36)))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(spring) { currentPage = index }
                    }
            }
        }
    }

    private func currentFolder(_ id: String) -> FolderRecord? {
        model.entries.compactMap(\.folder).first { $0.id == id }
    }

    // MARK: - Folder Layer

    @ViewBuilder private func folderLayer(_ folder: FolderRecord) -> some View {
        let apps = model.apps(in: folder)
        let metrics = folderPanelMetrics(appCount: apps.count)
        let progress = effectiveFolderReveal
        let sourceFrame = folderSourceFrame ?? sourceFrame(forFolderID: folder.id)
        let targetCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let contentHeight = metrics.visiblePanelHeight + 42
        let initialScale = min(
            0.22,
            max(0.075, min(sourceFrame.width / max(metrics.panelWidth, 1), sourceFrame.height / max(contentHeight, 1)))
        )
        let zoomScale = initialScale + (1 - initialScale) * progress
        let zoomOffset = CGSize(
            width: (sourceCenter.x - targetCenter.x) * (1 - progress),
            height: (sourceCenter.y - targetCenter.y) * (1 - progress)
        )
        let panelOpacity = min(1, progress * 1.35)

        ZStack {
            Color.black.opacity(Double(0.62 * progress))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeFolder() }
                .animation(.easeOut(duration: 0.18), value: folderEjecting)

            VStack(spacing: 16) {
                folderTitle(folder)

                GlassEffectContainer(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: metrics.needsScroll) {
                        folderGrid(apps: apps, folder: folder, metrics: metrics)
                    }
                    .frame(width: metrics.panelWidth, height: metrics.visiblePanelHeight)
                    .clipped()
                    .glassEffect(.regular.tint(Color.black.opacity(0.18)).interactive(false), in: .rect(cornerRadius: 28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.58),
                                        Color.white.opacity(0.18),
                                        Color.black.opacity(0.24)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 2.2)
                            .blur(radius: 1.3)
                            .mask(
                                LinearGradient(
                                    colors: [.white, .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                    )
                    .shadow(color: .white.opacity(0.12), radius: 2, y: -1)
                    .shadow(color: .black.opacity(0.46), radius: 34, y: 16)
                }
            }
            .padding(.horizontal, 56)
            .opacity(Double(panelOpacity))
            .scaleEffect(zoomScale, anchor: .center)
            .offset(zoomOffset)
            .animation(.easeOut(duration: 0.18), value: folderEjecting)
            .animation(.easeOut(duration: 0.18), value: closingFromFolderEject)

            if let folderDragID {
                AppIconView(model: model, appID: folderDragID, onLaunch: { _ in })
                    .frame(width: metrics.cell.width, height: metrics.cell.height)
                    .scaleEffect(1.16)
                    .shadow(color: .black.opacity(0.46), radius: 16, y: 8)
                    .position(folderDragPoint)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(CellFramePreference.self) { folderFrames = $0 }
    }

    private func folderPanelMetrics(appCount: Int) -> FolderPanelMetrics {
        let icon = min(settings.iconSize, 86)
        let cell = CGSize(width: icon + 26, height: icon + 38)
        let columns = min(10, max(1, appCount))
        let rows = max(1, Int(ceil(Double(appCount) / Double(columns))))
        let horizontalSpacing: CGFloat = 18
        let verticalSpacing: CGFloat = 18
        let panelWidth = min(
            size.width - 112,
            max(560, CGFloat(columns) * cell.width + CGFloat(columns - 1) * horizontalSpacing + 54)
        )
        let naturalPanelHeight = CGFloat(rows) * cell.height + CGFloat(rows - 1) * verticalSpacing + 42
        let maxPanelHeight = max(240, size.height - 220)
        let visiblePanelHeight = min(naturalPanelHeight, maxPanelHeight)

        return FolderPanelMetrics(
            cell: cell,
            columns: columns,
            rows: rows,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            panelWidth: panelWidth,
            naturalPanelHeight: naturalPanelHeight,
            visiblePanelHeight: visiblePanelHeight
        )
    }

    private func folderGrid(apps: [AppRecord], folder: FolderRecord, metrics: FolderPanelMetrics) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(metrics.cell.width), spacing: metrics.horizontalSpacing),
                count: metrics.columns
            ),
            spacing: metrics.verticalSpacing
        ) {
            ForEach(apps, id: \.id) { app in
                folderAppCell(app: app, folder: folder, cell: metrics.cell)
            }
        }
        .padding(.horizontal, 27)
        .padding(.vertical, 21)
        .frame(width: metrics.panelWidth)
    }

    private func currentExpandedFolderPanelRect() -> CGRect? {
        guard let folderID = presentedFolderID,
              let folder = currentFolder(folderID) else { return nil }
        let metrics = folderPanelMetrics(appCount: model.apps(in: folder).count)
        return CGRect(
            x: (size.width - metrics.panelWidth) / 2,
            y: (size.height - metrics.visiblePanelHeight) / 2,
            width: metrics.panelWidth,
            height: metrics.visiblePanelHeight
        )
    }

    private func currentCollapsedFolderHitRect() -> CGRect? {
        guard let folderID = presentedFolderID else { return nil }
        let source = folderSourceFrame ?? sourceFrame(forFolderID: folderID)
        let side = max(44, settings.iconSize)
        return CGRect(
            x: source.midX - side / 2,
            y: source.midY - side / 2,
            width: side,
            height: side
        )
    }

    @ViewBuilder private func folderTitle(_ folder: FolderRecord) -> some View {
        if editingFolderTitle {
            TextField("", text: $titleDraft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: 230)
                .focused($folderTitleFocused)
                .onAppear { folderTitleFocused = true }
                .onSubmit {
                    model.renameFolder(folder.id, to: titleDraft)
                    editingFolderTitle = false
                }
        } else {
            Text(folder.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.42), radius: 6, y: 2)
                .onTapGesture {
                    titleDraft = folder.name
                    editingFolderTitle = true
                }
        }
    }

    private func folderAppCell(app: AppRecord, folder: FolderRecord, cell: CGSize) -> some View {
        AppIconView(model: model, appID: app.id, onLaunch: onLaunch)
            .frame(width: cell.width, height: cell.height)
            .opacity(folderDragID == app.id ? 0.28 : 1)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CellFramePreference.self,
                        value: ["app:" + app.id: proxy.frame(in: .named(canvasSpace))]
                    )
                }
            )
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named(canvasSpace))
                    .onChanged { value in
                        folderDragID = app.id
                        folderDragPoint = value.location
                        let shouldEject = !isInsideFolderPanel(value.location)
                        if shouldEject != folderEjecting {
                            withAnimation(.easeOut(duration: 0.18)) {
                                folderEjecting = shouldEject
                            }
                        }
                        updateFolderEjectPreview(appID: app.id, at: value.location)
                    }
                    .onEnded { value in
                        finishFolderDrag(appID: app.id, folder: folder, at: value.location)
                    }
            )
            .contextMenu {
                Button("打开") { onLaunch(app.id) }
                Button("移出文件夹") {
                    model.removeFromFolder(appID: app.id, folderID: folder.id)
                    pages = buildPages()
                    if model.apps(in: folder).count <= 1 { closeFolder() }
                }
            }
    }

    private func isInsideFolderCells(_ point: CGPoint) -> Bool {
        folderFrames.contains { key, rect in
            key.hasPrefix("app:") && rect.insetBy(dx: -48, dy: -48).contains(point)
        }
    }

    private func isInsideFolderPanel(_ point: CGPoint) -> Bool {
        if folderEjecting || closingFromFolderEject || effectiveFolderReveal < 0.5 {
            guard let collapsed = currentCollapsedFolderHitRect() else {
                return isInsideFolderCells(point)
            }
            return collapsed.contains(point)
        }

        guard let panel = currentExpandedFolderPanelRect() else {
            return isInsideFolderCells(point)
        }
        return panel.insetBy(dx: -30, dy: -58).contains(point)
    }

    private func finishFolderDrag(appID: String, folder: FolderRecord, at point: CGPoint) {
        defer {
            folderDragID = nil
            if !closingFromFolderEject {
                folderEjecting = false
            }
            lastFolderEjectPreviewKey = nil
        }

        let sourceKey = "app:" + appID
        if isInsideFolderPanel(point),
           let hit = folderFrames.first(where: {
               $0.key.hasPrefix("app:") && $0.key != sourceKey && $0.value.contains(point)
           }) {
            previewPages = nil
            let targetID = String(hit.key.dropFirst(4))
            guard let source = folder.appIDs.firstIndex(of: appID),
                  let target = folder.appIDs.firstIndex(of: targetID) else { return }
            let insertAfter = point.x > hit.value.midX
            model.reorderInFolder(folder.id, from: source, to: insertAfter ? target + 1 : target)
            return
        }

        if isInsideFolderPanel(point) {
            previewPages = nil
            return
        }

        model.detachFromFolderForLayout(appID: appID, folderID: folder.id)
        closingFromFolderEject = true
        model.openFolderID = nil
        pages = buildPages()

        var layout = pages
        let entry = LaunchEntry.app(appID)

        var target = targetSlot(for: point)
        while target.page >= layout.count { layout.append([]) }
        target.index = min(max(target.index, 0), layout[target.page].count)
        layout[target.page].insert(entry, at: target.index)
        cascadeOverflow(&layout)
        let committed = clean(layout)
        pages = committed
        previewPages = nil
        model.commitPages(committed)
    }

    private func updateFolderEjectPreview(appID: String, at point: CGPoint) {
        guard folderDragID == appID else { return }

        if isInsideFolderPanel(point) {
            previewPages = nil
            lastFolderEjectPreviewKey = nil
            return
        }

        let target = targetSlot(for: point)
        let key = "\(target.page):\(target.index)"
        guard key != lastFolderEjectPreviewKey else { return }
        lastFolderEjectPreviewKey = key

        var layout = pages
        _ = removeEntry("app:" + appID, from: &layout)
        while target.page >= layout.count { layout.append([]) }
        let insertIndex = min(max(target.index, 0), layout[target.page].count)
        layout[target.page].insert(.app(appID), at: insertIndex)
        cascadeOverflow(&layout)

        withAnimation(flow) {
            previewPages = clean(layout)
        }
    }

    private func closeFolder() {
        model.openFolderID = nil
    }
}
