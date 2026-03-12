import XCTest

@MainActor
final class ReportFlowCoordinatorTests: XCTestCase {

    private var coordinator: ReportFlowCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = ReportFlowCoordinator()
    }

    // MARK: - Trigger Detection

    func testDetectTriggerMatchesExact() {
        XCTAssertTrue(coordinator.detectReportTrigger("prepare my doctor visit summary"))
    }

    func testDetectTriggerMatchesPartial() {
        XCTAssertTrue(coordinator.detectReportTrigger("Can you prepare my doctor summary please?"))
    }

    func testDetectTriggerCaseInsensitive() {
        XCTAssertTrue(coordinator.detectReportTrigger("PREPARE MY DOCTOR VISIT SUMMARY"))
    }

    func testDetectTriggerIgnoresUnrelated() {
        XCTAssertFalse(coordinator.detectReportTrigger("How's the weather today?"))
    }

    func testDetectTriggerMatchesHealthReport() {
        XCTAssertTrue(coordinator.detectReportTrigger("I need a health report"))
    }

    func testDetectTriggerRespectsFeatureFlag() {
        let flags = FeatureFlagService()
        flags.doctorReportEnabled = false
        let gated = ReportFlowCoordinator(featureFlags: flags)
        XCTAssertFalse(gated.detectReportTrigger("prepare my doctor visit summary"))
    }

    // MARK: - Begin Flow

    func testBeginFlowSetsState() {
        let response = coordinator.beginReportFlow()
        XCTAssertEqual(coordinator.flowState, .awaitingPeriod)
        XCTAssertTrue(response.contains("time period"))
    }

    // MARK: - Period Selection

    func testPeriodSelectionMatchesTwoWeeks() {
        coordinator.flowState = .awaitingPeriod
        let result = coordinator.handlePeriodSelection("last two weeks")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.days, 14)
        XCTAssertEqual(coordinator.flowState, .generating)
    }

    func testPeriodSelectionMatchesLastMonth() {
        coordinator.flowState = .awaitingPeriod
        let result = coordinator.handlePeriodSelection("past month")
        XCTAssertEqual(result?.days, 30)
    }

    func testPeriodSelectionMatchesSinceLastVisit() {
        coordinator.flowState = .awaitingPeriod
        let result = coordinator.handlePeriodSelection("since my last visit")
        XCTAssertEqual(result?.days, 90)
    }

    func testPeriodSelectionFallbackDefault() {
        coordinator.flowState = .awaitingPeriod
        let result = coordinator.handlePeriodSelection("I don't know, whatever makes sense")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.days, 14, "Should default to 14 days")
    }

    // MARK: - Report Generation

    func testGenerateReportReturnsVerbalSummary() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2), moodScore: 3, sleepHours: 7)
        ]
        coordinator.flowState = .generating

        let response = coordinator.generateReport(days: 7, checkIns: checkIns, medications: [], userName: "Test")

        XCTAssertFalse(response.isEmpty)
        XCTAssertEqual(coordinator.flowState, .presenting)
        XCTAssertNotNil(coordinator.verbalSummary)
    }

    #if canImport(UIKit)
    func testGenerateReportCreatesPDF() {
        let checkIns = [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2), moodScore: 3, sleepHours: 7)
        ]
        coordinator.flowState = .generating

        _ = coordinator.generateReport(days: 7, checkIns: checkIns, medications: [], userName: "Test")

        XCTAssertNotNil(coordinator.generatedPDFData)
        XCTAssertFalse(coordinator.generatedPDFData!.isEmpty)
    }
    #endif

    // MARK: - Presentation Response

    func testPresentationShareDetected() {
        coordinator.flowState = .presenting
        coordinator.verbalSummary = "Test summary"
        let result = coordinator.handlePresentationResponse("share it")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.action, .share)
    }

    func testPresentationReadMoreDetected() {
        coordinator.flowState = .presenting
        coordinator.verbalSummary = "Test summary"
        let result = coordinator.handlePresentationResponse("tell me more")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.action, .readMore)
    }

    func testPresentationDismissDetected() {
        coordinator.flowState = .presenting
        coordinator.verbalSummary = "Test summary"
        let result = coordinator.handlePresentationResponse("no thanks, that's it")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.action, .dismiss)
    }

    func testFlowResetsAfterDismiss() {
        coordinator.flowState = .presenting
        coordinator.verbalSummary = "Test"
        _ = coordinator.handlePresentationResponse("done")
        XCTAssertEqual(coordinator.flowState, .idle)
        XCTAssertNil(coordinator.generatedPDFData)
        XCTAssertNil(coordinator.verbalSummary)
    }

    func testPresentationUnrecognizedReturnsNil() {
        coordinator.flowState = .presenting
        let result = coordinator.handlePresentationResponse("what's the weather?")
        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
}
