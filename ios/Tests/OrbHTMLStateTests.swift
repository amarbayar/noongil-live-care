import XCTest

final class OrbHTMLStateTests: XCTestCase {

    func testMapsRestingToNeutralHtmlState() {
        XCTAssertEqual(OrbState.resting.htmlState, .neutral)
    }

    func testMapsProcessingToThinkingHtmlState() {
        XCTAssertEqual(OrbState.processing.htmlState, .thinking)
    }

    func testMapsSpeakingToSpeakingHtmlState() {
        XCTAssertEqual(OrbState.speaking.htmlState, .speaking)
    }
}
