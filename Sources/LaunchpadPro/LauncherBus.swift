import SwiftUI

/// Bridges AppKit-level trackpad / mouse scroll events (captured by the overlay
/// controller) into the SwiftUI paged grid.
@MainActor
final class LauncherBus: ObservableObject {
    static let shared = LauncherBus()

    // Discrete page flips (mouse wheel).
    @Published var nextPageTick: Int = 0
    @Published var prevPageTick: Int = 0

    // Continuous, finger-following trackpad swipe.
    @Published var scrollTick: Int = 0      // bumped on each incremental delta
    @Published var scrollEndTick: Int = 0   // bumped when the swipe ends -> snap
    var scrollDX: CGFloat = 0               // last incremental horizontal delta

    // Bumped each time the launcher is shown, so the canvas can clear any
    // interrupted drag state.
    @Published var resetTick: Int = 0

    func requestNextPage() { nextPageTick &+= 1 }
    func requestPrevPage() { prevPageTick &+= 1 }

    func liveScroll(_ dx: CGFloat) { scrollDX = dx; scrollTick &+= 1 }
    func endScroll() { scrollEndTick &+= 1 }
}
