import XCTest

final class CompanionHomeBackgroundStyleTests: XCTestCase {

    func testCalmBackgroundMatchesHtmlReferenceGradient() {
        let style = CompanionHomeBackgroundStyle.make(for: .resting)

        XCTAssertEqual(style.top.red, 0.0, accuracy: 0.001)
        XCTAssertEqual(style.top.green, 198.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(style.top.blue, 1.0, accuracy: 0.001)
        XCTAssertEqual(style.middle.red, 74.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(style.middle.green, 84.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(style.middle.blue, 225.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(style.bottom.red, 142.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(style.bottom.green, 45.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(style.bottom.blue, 226.0 / 255.0, accuracy: 0.001)
    }

    func testThinkingBackgroundUsesDarkerBottomForContrast() {
        let calm = CompanionHomeBackgroundStyle.make(for: .resting)
        let thinking = CompanionHomeBackgroundStyle.make(for: .processing)

        XCTAssertLessThan(thinking.bottom.brightness, calm.bottom.brightness)
        XCTAssertGreaterThan(thinking.primaryText.alpha, 0.95)
    }
}
