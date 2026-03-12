import XCTest

final class OrbVisualStyleTests: XCTestCase {

    func testListeningStateExpandsComparedToCalm() {
        let calm = OrbVisualStyle.make(for: .resting, timeOfDay: .afternoon)
        let listening = OrbVisualStyle.make(for: .listening, timeOfDay: .afternoon)

        XCTAssertGreaterThan(listening.orbScale, calm.orbScale)
        XCTAssertGreaterThan(listening.wavePeakHeight, calm.wavePeakHeight)
    }

    func testThinkingStateRotatesFastest() {
        let calm = OrbVisualStyle.make(for: .resting, timeOfDay: .evening)
        let thinking = OrbVisualStyle.make(for: .processing, timeOfDay: .evening)
        let speaking = OrbVisualStyle.make(for: .speaking, timeOfDay: .evening)

        XCTAssertLessThan(thinking.rotationDuration, calm.rotationDuration)
        XCTAssertLessThan(thinking.rotationDuration, speaking.rotationDuration)
        XCTAssertLessThan(thinking.orbScale, 1.0)
    }

    func testSpeakingStateUsesWarmPulseAndTallWaveform() {
        let speaking = OrbVisualStyle.make(for: .speaking, timeOfDay: .morning)

        XCTAssertGreaterThan(speaking.speakingPulseScale, 1.0)
        XCTAssertGreaterThan(speaking.wavePeakHeight, 24)
        XCTAssertGreaterThan(speaking.glowOpacity, 0.2)
    }

    func testNightCalmStyleUsesDarkerBaseForContrast() {
        let afternoon = OrbVisualStyle.make(for: .resting, timeOfDay: .afternoon)
        let night = OrbVisualStyle.make(for: .resting, timeOfDay: .night)

        XCTAssertGreaterThan(afternoon.baseFill.brightness, night.baseFill.brightness)
        XCTAssertGreaterThan(night.shellShadowOpacity, afternoon.shellShadowOpacity)
    }

    func testHtmlReferenceCoreUsesStableStopLocations() {
        let calm = OrbVisualStyle.make(for: .resting, timeOfDay: .afternoon)

        XCTAssertEqual(calm.coreStopLocations.count, 4)
        XCTAssertEqual(calm.coreStopLocations[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(calm.coreStopLocations[1], 0.20, accuracy: 0.0001)
        XCTAssertEqual(calm.coreStopLocations[2], 0.55, accuracy: 0.0001)
        XCTAssertEqual(calm.coreStopLocations[3], 1.0, accuracy: 0.0001)
    }

    func testCalmStyleKeepsGlassShellSubtle() {
        let calm = OrbVisualStyle.make(for: .resting, timeOfDay: .afternoon)

        XCTAssertLessThanOrEqual(calm.shellFillOpacity, 0.12)
        XCTAssertLessThanOrEqual(calm.upperHighlightOpacity, 0.50)
        XCTAssertLessThanOrEqual(calm.innerRingOpacity, 0.05)
    }
}
