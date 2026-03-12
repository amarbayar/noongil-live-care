import XCTest

final class CompanionHomeOrbChromeTests: XCTestCase {

    func testRestingStateDoesNotShowStatusRing() {
        XCTAssertFalse(
            CompanionHomeOrbChrome.shouldShowStatusRing(
                isSessionActive: false,
                state: .resting
            )
        )
    }

    func testCheckInDueShowsStatusRingWhenIdle() {
        XCTAssertTrue(
            CompanionHomeOrbChrome.shouldShowStatusRing(
                isSessionActive: false,
                state: .checkInDue
            )
        )
    }

    func testActiveSessionDoesNotShowStatusRing() {
        XCTAssertFalse(
            CompanionHomeOrbChrome.shouldShowStatusRing(
                isSessionActive: true,
                state: .checkInDue
            )
        )
    }

    func testTapIsEnabledWhenSessionCanStart() {
        XCTAssertTrue(
            CompanionHomeOrbChrome.isTapEnabled(
                canStartSession: true,
                isSessionActive: false
            )
        )
    }

    func testTapIsEnabledWhenSessionIsAlreadyActive() {
        XCTAssertTrue(
            CompanionHomeOrbChrome.isTapEnabled(
                canStartSession: false,
                isSessionActive: true
            )
        )
    }

    func testTapIsDisabledOnlyWhenIdleAndUnavailable() {
        XCTAssertFalse(
            CompanionHomeOrbChrome.isTapEnabled(
                canStartSession: false,
                isSessionActive: false
            )
        )
    }

    func testOrbScaleShrinksWhenPressedAndInteractive() {
        XCTAssertLessThan(
            CompanionHomeOrbChrome.orbScale(
                isPressed: true,
                canStartSession: true,
                isSessionActive: false
            ),
            1.0
        )
    }

    func testOrbScaleStaysDefaultWhenNotInteractive() {
        XCTAssertEqual(
            CompanionHomeOrbChrome.orbScale(
                isPressed: true,
                canStartSession: false,
                isSessionActive: false
            ),
            1.0
        )
    }
}
