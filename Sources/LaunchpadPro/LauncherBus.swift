import SwiftUI

/// Bridges AppKit-level events (trackpad / mouse scroll-wheel paging) captured
/// by the overlay controller into the SwiftUI paged grid.
@MainActor
final class LauncherBus: ObservableObject {
    static let shared = LauncherBus()
    @Published var nextPageTick: Int = 0
    @Published var prevPageTick: Int = 0

    func requestNextPage() { nextPageTick &+= 1 }
    func requestPrevPage() { prevPageTick &+= 1 }
}
