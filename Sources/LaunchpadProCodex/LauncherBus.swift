import SwiftUI

@MainActor
final class LauncherBus: ObservableObject {
    static let shared = LauncherBus()

    @Published var nextPageTick: Int = 0
    @Published var previousPageTick: Int = 0
    @Published var liveScrollTick: Int = 0
    @Published var endScrollTick: Int = 0
    @Published var displayFrameTick: Int = 0
    @Published var resetTick: Int = 0

    var latestScrollDX: CGFloat = 0
    var swipeVelocity: CGFloat = 0
    var swipeEnergy: CGFloat = 0
    var displayFrameDuration: CFTimeInterval = 1.0 / 120.0

    func nextPage() { nextPageTick &+= 1 }
    func previousPage() { previousPageTick &+= 1 }
    func reset() { resetTick &+= 1 }

    func liveScroll(dx: CGFloat) {
        latestScrollDX = dx
        liveScrollTick &+= 1
    }

    func endScroll(velocity: CGFloat = 0, energy: CGFloat = 0) {
        swipeVelocity = velocity
        swipeEnergy = energy
        endScrollTick &+= 1
    }

    func displayFrame(duration: CFTimeInterval) {
        displayFrameDuration = duration > 0 ? duration : 1.0 / 120.0
        displayFrameTick &+= 1
    }
}
