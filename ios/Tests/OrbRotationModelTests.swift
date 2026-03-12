import XCTest

final class OrbRotationModelTests: XCTestCase {

    func testTransitionPreservesCurrentAngle() {
        var rotation = OrbRotationModel(anchorDegrees: 24, anchorTime: 0, duration: 8.0)
        let before = rotation.degrees(at: 2.75)

        rotation.transition(toDuration: 4.5, at: 2.75)
        let after = rotation.degrees(at: 2.75)

        XCTAssertEqual(after, before, accuracy: 0.0001)
    }

    func testShorterDurationAdvancesAngleFaster() {
        let slow = OrbRotationModel(anchorDegrees: 0, anchorTime: 0, duration: 8.0)
        let fast = OrbRotationModel(anchorDegrees: 0, anchorTime: 0, duration: 4.0)

        XCTAssertGreaterThan(fast.degrees(at: 1.0), slow.degrees(at: 1.0))
    }

    func testReduceMotionPinsAngleToAccessibleValue() {
        let rotation = OrbRotationModel(anchorDegrees: 90, anchorTime: 0, duration: 8.0)

        XCTAssertEqual(rotation.degrees(at: 10.0, reduceMotion: true), 18.0, accuracy: 0.0001)
    }
}
