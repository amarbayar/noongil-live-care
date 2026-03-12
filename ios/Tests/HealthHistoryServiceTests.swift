import XCTest

final class HealthHistoryServiceTests: XCTestCase {

    // MARK: - Mood Trend

    func testMoodTrendExtractsScores() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0), moodScore: 4),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), moodScore: 2),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2), moodScore: 3)
        ]

        let trend = HealthHistoryService.moodTrend(from: checkIns)

        XCTAssertEqual(trend.count, 3)
        XCTAssertEqual(trend[0].score, 4)
        XCTAssertEqual(trend[1].score, 2)
        XCTAssertEqual(trend[2].score, 3)
    }

    func testMoodTrendSkipsCheckInsWithoutMood() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0), moodScore: 3),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1)) // no mood
        ]

        let trend = HealthHistoryService.moodTrend(from: checkIns)
        XCTAssertEqual(trend.count, 1)
    }

    func testAverageMood() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0), moodScore: 4),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), moodScore: 2)
        ]

        let avg = HealthHistoryService.averageMood(from: checkIns)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!, 3.0, accuracy: 0.01)
    }

    func testAverageMoodReturnsNilForEmpty() {
        XCTAssertNil(HealthHistoryService.averageMood(from: []))
    }

    // MARK: - Sleep Trend

    func testSleepTrendExtractsHours() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0), sleepHours: 7.5),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), sleepHours: 6.0)
        ]

        let trend = HealthHistoryService.sleepTrend(from: checkIns)

        XCTAssertEqual(trend.count, 2)
        XCTAssertEqual(trend[0].hours, 7.5, accuracy: 0.01)
        XCTAssertEqual(trend[1].hours, 6.0, accuracy: 0.01)
    }

    func testSleepTrendSkipsCheckInsWithoutSleep() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0)),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), sleepHours: 8.0)
        ]

        let trend = HealthHistoryService.sleepTrend(from: checkIns)
        XCTAssertEqual(trend.count, 1)
    }

    func testAverageSleep() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0), sleepHours: 8.0),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), sleepHours: 6.0)
        ]

        let avg = HealthHistoryService.averageSleep(from: checkIns)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!, 7.0, accuracy: 0.01)
    }

    func testAverageSleepReturnsNilForEmpty() {
        XCTAssertNil(HealthHistoryService.averageSleep(from: []))
    }

    // MARK: - Symptom Summary

    func testSymptomSummaryCounts() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0))
        c1.symptoms = [
            SymptomEntry(type: .tremor, severity: 3),
            SymptomEntry(type: .fatigue, severity: 2)
        ]
        var c2 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c2.symptoms = [
            SymptomEntry(type: .tremor, severity: 4)
        ]

        let summary = HealthHistoryService.symptomSummary(from: [c1, c2])

        XCTAssertEqual(summary.count, 2)
        // Tremor should be first (most occurrences)
        XCTAssertEqual(summary[0].type, .tremor)
        XCTAssertEqual(summary[0].occurrences, 2)
        XCTAssertNotNil(summary[0].averageSeverity)
        XCTAssertEqual(summary[0].averageSeverity!, 3.5, accuracy: 0.01)
        XCTAssertEqual(summary[1].type, .fatigue)
        XCTAssertEqual(summary[1].occurrences, 1)
    }

    func testSymptomSummaryEmptyForNoSymptoms() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0))
        ]

        let summary = HealthHistoryService.symptomSummary(from: checkIns)
        XCTAssertTrue(summary.isEmpty)
    }

    // MARK: - Daily Summaries

    func testDailySummariesMapCheckIns() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(0), moodScore: 4, sleepHours: 7.0)
        c1.symptoms = [SymptomEntry(type: .tremor, severity: 2)]

        let summaries = HealthHistoryService.dailySummaries(from: [c1])

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].moodScore, 4)
        XCTAssertNotNil(summaries[0].sleepHours)
        XCTAssertEqual(summaries[0].sleepHours!, 7.0, accuracy: 0.01)
        XCTAssertEqual(summaries[0].symptomCount, 1)
        XCTAssertEqual(summaries[0].checkInType, .morning)
    }

    func testDailySummariesHandleMissingData() {
        let c1 = CheckIn.testInstance(userId: "u", type: .evening, startedAt: daysAgo(0))

        let summaries = HealthHistoryService.dailySummaries(from: [c1])

        XCTAssertEqual(summaries.count, 1)
        XCTAssertNil(summaries[0].moodScore)
        XCTAssertNil(summaries[0].sleepHours)
        XCTAssertEqual(summaries[0].symptomCount, 0)
    }

    func testDailySummariesFallBackToAISummaryForMoodAndSleep() {
        var checkIn = CheckIn.testInstance(userId: "u", type: .adhoc, startedAt: daysAgo(0))
        checkIn.aiSummary = "Mood: calm. Sleep: seven hours. Symptoms: none. Medications: yes"

        let summaries = HealthHistoryService.dailySummaries(from: [checkIn])

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].moodDescription, "Calm")
        XCTAssertEqual(summaries[0].moodScore, 4)
        XCTAssertNotNil(summaries[0].sleepHours)
        XCTAssertEqual(summaries[0].sleepHours!, 7.0, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
}
