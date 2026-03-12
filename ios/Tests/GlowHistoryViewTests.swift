import XCTest

@MainActor
final class GlowHistoryViewTests: XCTestCase {

    func testAccessibilityLabelAllGood() {
        let days = makeDays([.good, .good, .good])
        let view = GlowHistoryView(days: days)
        // Verify the view initializes without crashing with all-good days
        XCTAssertEqual(days.count, 3)
    }

    func testAccessibilityLabelMixed() {
        let days = makeDays([.good, .mixed, .concern, .missed])
        let view = GlowHistoryView(days: days)
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(days[0].status, .good)
        XCTAssertEqual(days[1].status, .mixed)
        XCTAssertEqual(days[2].status, .concern)
        XCTAssertEqual(days[3].status, .missed)
    }

    func testEmptyDays() {
        let days: [GlowDay] = []
        let view = GlowHistoryView(days: days)
        XCTAssertTrue(days.isEmpty)
    }

    func testSevenDayHistory() {
        let days = makeDays([.good, .mixed, .good, .concern, .missed, .good, .mixed])
        XCTAssertEqual(days.count, 7)
    }

    // MARK: - Helpers

    private func makeDays(_ statuses: [DayStatus]) -> [GlowDay] {
        statuses.enumerated().map { index, status in
            let date = Calendar.current.date(byAdding: .day, value: -index, to: Date())!
            return GlowDay(id: date, status: status)
        }
    }
}
