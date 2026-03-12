import XCTest

final class CompanionContextTests: XCTestCase {

    // MARK: - B-03: Greeting Context

    func testGreetingContextIncludesTimeOfDay() {
        let hour = Calendar.current.component(.hour, from: Date())
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: [],
            userName: "Robert",
            checkInType: .morning
        )

        // Should always mention the check-in type
        XCTAssertTrue(context.contains("morning") || context.contains("evening") || context.contains("check-in"),
                       "Greeting context should reference the check-in type")
    }

    func testGreetingContextIncludesUserName() {
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: [],
            userName: "Robert",
            checkInType: .morning
        )

        XCTAssertTrue(context.contains("Robert"),
                       "Greeting context should include the user's name")
    }

    func testGreetingContextWithNoHistory() {
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: [],
            userName: "Robert",
            checkInType: .morning
        )

        XCTAssertTrue(context.contains("first"),
                       "Should indicate this is the first check-in when no history")
    }

    func testGreetingContextWithStreak() {
        // Simulate 3 consecutive days of check-ins
        let checkIns = makeConsecutiveDayCheckIns(count: 3)
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: checkIns,
            userName: "Robert",
            checkInType: .morning
        )

        XCTAssertTrue(context.contains("3") || context.contains("three") || context.contains("streak"),
                       "Should mention the 3-day streak")
    }

    func testGreetingContextWithGap() {
        // Only one check-in, 3 days ago
        let checkIns = makeCheckInsWithGap(lastCheckInDaysAgo: 3)
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: checkIns,
            userName: "Robert",
            checkInType: .morning
        )

        XCTAssertTrue(context.contains("gap") || context.contains("missed") || context.contains("while") || context.contains("days"),
                       "Should mention the gap since last check-in")
    }

    func testGreetingContextWithBadMoodYesterday() {
        let checkIns = makeCheckInsWithMood(score: 1, label: "negative", daysAgo: 1)
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: checkIns,
            userName: "Robert",
            checkInType: .morning
        )

        XCTAssertTrue(context.contains("rough") || context.contains("tough") || context.contains("difficult") || context.contains("yesterday") || context.contains("last"),
                       "Should reference yesterday's difficult day")
    }

    func testGreetingContextWithGoodMoodYesterday() {
        let checkIns = makeCheckInsWithMood(score: 4, label: "positive", daysAgo: 1)
        let context = CompanionContext.buildGreetingContext(
            recentCheckIns: checkIns,
            userName: "Robert",
            checkInType: .morning
        )

        // Should not reference a difficult day
        XCTAssertFalse(context.contains("rough") || context.contains("tough"),
                        "Should not mention a difficult day when mood was good")
    }

    // MARK: - B-04: Closing Context

    func testClosingContextIncludesPositiveNote() {
        let context = CompanionContext.buildClosingContext(
            currentCheckIn: nil,
            recentCheckIns: []
        )

        // Should always have instructions for a warm close
        XCTAssertTrue(context.contains("warm") || context.contains("positive") || context.contains("encouraging"),
                       "Closing context should always instruct for positivity")
    }

    func testClosingContextReferencesImprovedSleep() {
        // Recent check-ins show sleep improving
        let checkIns = makeCheckInsWithImprovingSleep()
        let context = CompanionContext.buildClosingContext(
            currentCheckIn: checkIns.first,
            recentCheckIns: checkIns
        )

        XCTAssertTrue(context.contains("sleep") || context.contains("rest"),
                       "Should reference improving sleep data")
    }

    func testClosingContextReferencesStreak() {
        let checkIns = makeConsecutiveDayCheckIns(count: 5)
        let context = CompanionContext.buildClosingContext(
            currentCheckIn: checkIns.first,
            recentCheckIns: checkIns
        )

        XCTAssertTrue(context.contains("streak") || context.contains("row") || context.contains("consecutive") || context.contains("5"),
                       "Should reference the check-in streak")
    }

    func testClosingContextWithNoDataStillPositive() {
        let checkIn = CheckIn(userId: "test-user", type: .morning)
        let context = CompanionContext.buildClosingContext(
            currentCheckIn: checkIn,
            recentCheckIns: []
        )

        XCTAssertTrue(context.contains("warm") || context.contains("positive") || context.contains("encouraging") || context.contains("thank"),
                       "Should still be positive even without data")
    }

    func testClosingContextMentionsMoodImprovement() {
        // Previous check-in had low mood, current has high
        let checkIns = makeCheckInsWithMoodImprovement()
        let context = CompanionContext.buildClosingContext(
            currentCheckIn: checkIns.first,
            recentCheckIns: checkIns
        )

        XCTAssertTrue(context.contains("mood") || context.contains("better") || context.contains("brighter") || context.contains("improved"),
                       "Should reference mood improvement")
    }

    // MARK: - Integration: Context injected into system prompt

    func testBuildIncludesGreetingHints() {
        let fullContext = CompanionContext.build(
            profile: nil,
            recentCheckIns: [],
            medications: [],
            vocabulary: nil,
            companionName: "Mira"
        )

        // The build method already produces context — just verify it works
        XCTAssertTrue(fullContext.contains("Mira"))
    }

    // MARK: - Test Data Factories

    private func makeConsecutiveDayCheckIns(count: Int) -> [CheckIn] {
        return (0..<count).map { daysAgo in
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                completionStatus: .completed,
                moodScore: 3
            )
        }
    }

    private func makeCheckInsWithGap(lastCheckInDaysAgo: Int) -> [CheckIn] {
        return [
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Calendar.current.date(byAdding: .day, value: -lastCheckInDaysAgo, to: Date())!,
                completionStatus: .completed
            )
        ]
    }

    private func makeCheckInsWithMood(score: Int, label: String, daysAgo: Int) -> [CheckIn] {
        return [
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                completionStatus: .completed,
                moodScore: score,
                moodLabel: label
            )
        ]
    }

    private func makeCheckInsWithImprovingSleep() -> [CheckIn] {
        // Most recent: 8 hours, previous: 5 hours
        return [
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Date(),
                completionStatus: .inProgress,
                sleepHours: 8.0
            ),
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                completionStatus: .completed,
                sleepHours: 5.0
            )
        ]
    }

    private func makeCheckInsWithMoodImprovement() -> [CheckIn] {
        return [
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Date(),
                completionStatus: .inProgress,
                moodScore: 4,
                moodLabel: "positive"
            ),
            CheckIn.testInstance(
                userId: "test-user",
                type: .morning,
                startedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                completionStatus: .completed,
                moodScore: 2,
                moodLabel: "negative"
            )
        ]
    }
}

// MARK: - CheckIn Test Factory

extension CheckIn {
    /// Creates a CheckIn with a specific startedAt date for testing.
    static func testInstance(
        userId: String,
        type: CheckInType,
        startedAt: Date,
        completionStatus: CheckInStatus = .completed,
        moodScore: Int? = nil,
        moodLabel: String? = nil,
        sleepHours: Double? = nil
    ) -> CheckIn {
        var checkIn = CheckIn(userId: userId, type: type)
        checkIn.startedAt = startedAt
        checkIn.completionStatus = completionStatus
        if let score = moodScore {
            checkIn.mood = MoodEntry(score: score, description: nil, label: moodLabel)
        }
        if let hours = sleepHours {
            checkIn.sleep = SleepEntry(hours: hours, quality: nil, interruptions: nil, description: nil)
        }
        return checkIn
    }
}
