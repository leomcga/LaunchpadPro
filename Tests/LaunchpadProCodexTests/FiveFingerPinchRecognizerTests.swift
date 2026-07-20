import XCTest
@testable import LaunchpadProCodex

final class FiveFingerPinchRecognizerTests: XCTestCase {
    func testContractingFiveFingerCloudTriggersOnce() {
        var recognizer = FiveFingerPinchRecognizer()

        XCTAssertFalse(recognizer.process(points: points(scale: 1.0), timestamp: 0.0))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.90), timestamp: 0.1))
        XCTAssertTrue(recognizer.process(points: points(scale: 0.89), timestamp: 0.2))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.50), timestamp: 0.3))

        XCTAssertFalse(recognizer.process(points: [], timestamp: 0.4))
        XCTAssertFalse(recognizer.process(points: points(scale: 1.0), timestamp: 0.5))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.90), timestamp: 0.6))
        XCTAssertTrue(recognizer.process(points: points(scale: 0.89), timestamp: 0.7))
    }

    func testFiveFingerSwipeDoesNotTrigger() {
        var recognizer = FiveFingerPinchRecognizer()

        for step in 0..<8 {
            let translated = points(scale: 1.0).map {
                MTPoint(x: $0.x + Float(step) * 0.025, y: $0.y)
            }
            XCTAssertFalse(
                recognizer.process(points: translated, timestamp: Double(step) * 0.1)
            )
        }
    }

    func testFourFingersCannotStartGesture() {
        var recognizer = FiveFingerPinchRecognizer()

        XCTAssertFalse(
            recognizer.process(points: Array(points(scale: 1.0).prefix(4)), timestamp: 0.0)
        )
        XCTAssertFalse(
            recognizer.process(points: Array(points(scale: 0.4).prefix(4)), timestamp: 0.1)
        )
    }

    func testTinyFiveFingerMovementDoesNotTrigger() {
        var recognizer = FiveFingerPinchRecognizer()

        XCTAssertFalse(recognizer.process(points: points(scale: 1.0), timestamp: 0.0))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.94), timestamp: 0.1))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.92), timestamp: 0.2))
    }

    func testFrameGapStartsANewGestureWithoutReleaseFrame() {
        var recognizer = FiveFingerPinchRecognizer()

        XCTAssertFalse(recognizer.process(points: points(scale: 1.0), timestamp: 0.0))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.90), timestamp: 0.1))
        XCTAssertTrue(recognizer.process(points: points(scale: 0.89), timestamp: 0.2))

        XCTAssertFalse(recognizer.process(points: points(scale: 1.0), timestamp: 0.7))
        XCTAssertFalse(recognizer.process(points: points(scale: 0.90), timestamp: 0.8))
        XCTAssertTrue(recognizer.process(points: points(scale: 0.89), timestamp: 0.9))
    }

    private func points(scale: Float) -> [MTPoint] {
        let center = MTPoint(x: 0.5, y: 0.5)
        let offsets: [MTPoint] = [
            MTPoint(x: -0.24, y: -0.10),
            MTPoint(x: -0.13, y: 0.18),
            MTPoint(x: 0.00, y: 0.24),
            MTPoint(x: 0.14, y: 0.17),
            MTPoint(x: 0.23, y: -0.09)
        ]
        return offsets.map {
            MTPoint(x: center.x + $0.x * scale, y: center.y + $0.y * scale)
        }
    }
}
