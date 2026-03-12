import XCTest

final class CompanionContextMinimizationTests: XCTestCase {

    // MARK: - moodLabel

    func testMoodLabelLow() {
        XCTAssertEqual(CompanionContext.moodLabel(1), "low")
        XCTAssertEqual(CompanionContext.moodLabel(2), "low")
    }

    func testMoodLabelModerate() {
        XCTAssertEqual(CompanionContext.moodLabel(3), "moderate")
    }

    func testMoodLabelGood() {
        XCTAssertEqual(CompanionContext.moodLabel(4), "good")
        XCTAssertEqual(CompanionContext.moodLabel(5), "good")
    }

    func testMoodLabelOutOfRange() {
        XCTAssertEqual(CompanionContext.moodLabel(0), "moderate")
        XCTAssertEqual(CompanionContext.moodLabel(6), "moderate")
    }

    // MARK: - Recent Check-ins uses prefix(3)

    func testRecentCheckInsUsesThree() {
        let checkIns = (0..<5).map { i in
            var c = CheckIn(userId: "u1", type: .morning)
            c.startedAt = Date().addingTimeInterval(Double(-i) * 86400)
            c.mood = MoodEntry(score: 3 + (i % 3), description: "ok")
            return c
        }

        let context = CompanionContext.build(
            profile: nil,
            recentCheckIns: checkIns,
            medications: [],
            vocabulary: nil
        )

        // Count how many check-in date lines appear (lines starting with "- ")
        let checkInLines = context
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("- ") && $0.contains("(morning)") }

        XCTAssertEqual(checkInLines.count, 3, "Should include only 3 recent check-ins, not 5")
    }

    // MARK: - Dosages omitted

    func testMedicationDosagesOmitted() {
        let med = Medication(
            userId: "u1",
            name: "Levodopa",
            dosage: "100mg",
            schedule: ["08:00", "20:00"]
        )

        let context = CompanionContext.build(
            profile: nil,
            recentCheckIns: [],
            medications: [med],
            vocabulary: nil
        )

        XCTAssertTrue(context.contains("Levodopa"), "Should include medication name")
        XCTAssertFalse(context.contains("100mg"), "Should NOT include dosage")
        XCTAssertTrue(context.contains("08:00"), "Should include schedule")
    }

    // MARK: - Week number omitted

    func testWeekNumberOmitted() {
        let context = CompanionContext.build(
            profile: nil,
            recentCheckIns: [],
            medications: [],
            vocabulary: nil
        )

        XCTAssertFalse(context.contains("Week "), "Should not include week number")
    }

    // MARK: - Patterns use qualitative labels

    func testPatternsUseQualitativeLabels() {
        var c1 = CheckIn(userId: "u1", type: .morning)
        c1.startedAt = Date()
        c1.mood = MoodEntry(score: 2, description: nil)
        c1.completionStatus = .completed

        var c2 = CheckIn(userId: "u1", type: .morning)
        c2.startedAt = Date().addingTimeInterval(-86400)
        c2.mood = MoodEntry(score: 4, description: nil)
        c2.completionStatus = .completed

        let patterns = CompanionContext.buildPatternsSection([c1, c2])

        // Should contain qualitative labels
        XCTAssertTrue(patterns.contains("low"), "Should use 'low' label")
        XCTAssertTrue(patterns.contains("good"), "Should use 'good' label")
        // Should NOT contain raw numeric scores like "4 →" or "→ 2"
        XCTAssertFalse(patterns.contains("4 →"), "Should not contain raw score '4 →'")
        XCTAssertFalse(patterns.contains("→ 2"), "Should not contain raw score '→ 2'")
    }
}
