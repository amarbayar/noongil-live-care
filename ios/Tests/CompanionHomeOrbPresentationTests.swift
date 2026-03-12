import XCTest

final class CompanionHomeOrbPresentationTests: XCTestCase {

    func testRestingPresentationWhenReadyToStart() {
        let presentation = CompanionHomeOrbPresentation.make(
            state: .resting,
            isSessionActive: false,
            canStartSession: true
        )

        XCTAssertEqual(presentation.title, "Calm")
        XCTAssertTrue(presentation.subtitle.contains("Tap the orb"))
    }

    func testListeningPresentation() {
        let presentation = CompanionHomeOrbPresentation.make(
            state: .listening,
            isSessionActive: true,
            canStartSession: true
        )

        XCTAssertEqual(presentation.title, "Listening")
        XCTAssertTrue(presentation.subtitle.contains("Speak naturally"))
    }

    func testProcessingPresentation() {
        let presentation = CompanionHomeOrbPresentation.make(
            state: .processing,
            isSessionActive: true,
            canStartSession: true,
            isConnecting: false
        )

        XCTAssertEqual(presentation.title, "Thinking")
        XCTAssertTrue(presentation.subtitle.contains("working through"))
    }

    func testProcessingPresentationWhileConnecting() {
        let presentation = CompanionHomeOrbPresentation.make(
            state: .processing,
            isSessionActive: true,
            canStartSession: true,
            isConnecting: true
        )

        XCTAssertEqual(presentation.title, "Connecting")
        XCTAssertTrue(presentation.subtitle.contains("getting ready"))
    }

    func testSpeakingPresentation() {
        let presentation = CompanionHomeOrbPresentation.make(
            state: .speaking,
            isSessionActive: true,
            canStartSession: true
        )

        XCTAssertEqual(presentation.title, "Speaking")
        XCTAssertTrue(presentation.subtitle.contains("talking back"))
    }

    func testErrorPresentationOffersRetry() {
        let presentation = CompanionHomeOrbPresentation.make(
            state: .error,
            isSessionActive: false,
            canStartSession: true
        )

        XCTAssertEqual(presentation.title, "Connection issue")
        XCTAssertEqual(presentation.accessibilityHint, "Tap the orb to retry the voice session")
    }
}
