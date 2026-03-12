import XCTest

@MainActor
final class OnboardingServiceTests: XCTestCase {

    private var service: OnboardingService!

    override func setUp() {
        super.setUp()
        service = OnboardingService()
    }

    // MARK: - Step Flow

    func testInitialStepIsWelcome() {
        XCTAssertEqual(service.currentStep, .welcome)
    }

    func testAdvanceMovesToNextStep() {
        service.advance()
        XCTAssertEqual(service.currentStep, .name)
    }

    func testFullStepSequence() {
        let expectedSteps: [OnboardingStep] = [
            .welcome, .name, .condition, .speechAssessment,
            .checkInSchedule, .complete
        ]

        for (i, expected) in expectedSteps.enumerated() {
            XCTAssertEqual(service.currentStep, expected, "Step \(i) mismatch")
            if i < expectedSteps.count - 1 {
                service.advance()
            }
        }
    }

    func testGoBackMovesToPreviousStep() {
        service.advance() // name
        service.advance() // condition
        service.goBack()
        XCTAssertEqual(service.currentStep, .name)
    }

    func testGoBackFromWelcomeStaysAtWelcome() {
        service.goBack()
        XCTAssertEqual(service.currentStep, .welcome)
    }

    func testCannotAdvancePastComplete() {
        // Advance to complete
        while service.currentStep != .complete {
            service.advance()
        }
        service.advance() // Should stay at complete
        XCTAssertEqual(service.currentStep, .complete)
    }

    // MARK: - Data Capture

    func testSetName() {
        service.userName = "Robert"
        XCTAssertEqual(service.userName, "Robert")
    }

    func testSetCondition() {
        service.selectedCondition = .parkinsons
        XCTAssertEqual(service.selectedCondition, .parkinsons)
    }

    func testSetSpeechAccommodation() {
        service.speechAccommodation = .moderate
        XCTAssertEqual(service.speechAccommodation, .moderate)
    }

    func testSetSchedule() {
        service.morningTime = "09:00"
        service.eveningTime = "21:00"
        XCTAssertEqual(service.morningTime, "09:00")
        XCTAssertEqual(service.eveningTime, "21:00")
    }

    // MARK: - Progress

    func testProgressAtWelcome() {
        XCTAssertEqual(service.progress, 0.0, accuracy: 0.01)
    }

    func testProgressAtComplete() {
        while service.currentStep != .complete {
            service.advance()
        }
        XCTAssertEqual(service.progress, 1.0, accuracy: 0.01)
    }

    func testProgressIncreases() {
        let first = service.progress
        service.advance()
        let second = service.progress
        XCTAssertGreaterThan(second, first)
    }

    // MARK: - Conditions

    func testConditionDisplayNames() {
        XCTAssertEqual(UserCondition.parkinsons.displayName, "Parkinson's")
        XCTAssertEqual(UserCondition.als.displayName, "ALS")
        XCTAssertEqual(UserCondition.ms.displayName, "MS")
        XCTAssertEqual(UserCondition.arthritis.displayName, "Arthritis")
        XCTAssertEqual(UserCondition.other.displayName, "Other")
    }
}
