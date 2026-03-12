import XCTest

@MainActor
final class EmergencyServiceTests: XCTestCase {

    private var service: EmergencyService!

    override func setUp() {
        super.setUp()
        service = EmergencyService()
    }

    // MARK: - Keyword Detection

    func testDetectsINeedHelp() {
        XCTAssertTrue(service.containsEmergencyTrigger("I need help"))
    }

    func testDetectsEmergency() {
        XCTAssertTrue(service.containsEmergencyTrigger("Mira, emergency"))
    }

    func testDetectsHelpMe() {
        XCTAssertTrue(service.containsEmergencyTrigger("help me please"))
    }

    func testDetectsCaseInsensitive() {
        XCTAssertTrue(service.containsEmergencyTrigger("HELP ME"))
        XCTAssertTrue(service.containsEmergencyTrigger("I NEED HELP"))
    }

    func testDoesNotTriggerOnNormalSpeech() {
        XCTAssertFalse(service.containsEmergencyTrigger("I slept well last night"))
        XCTAssertFalse(service.containsEmergencyTrigger("my tremor is moderate today"))
        XCTAssertFalse(service.containsEmergencyTrigger("I took my medication"))
    }

    func testDoesNotTriggerOnEmpty() {
        XCTAssertFalse(service.containsEmergencyTrigger(""))
    }

    func testDetectsPartialMatch() {
        XCTAssertTrue(service.containsEmergencyTrigger("Mira I need help right now"))
    }

    func testDetectsCallForHelp() {
        XCTAssertTrue(service.containsEmergencyTrigger("call for help"))
    }

    func testDetectsSOS() {
        XCTAssertTrue(service.containsEmergencyTrigger("SOS"))
    }

    // MARK: - Emergency State

    func testInitialStateIsInactive() {
        XCTAssertEqual(service.state, .inactive)
    }

    func testTriggerChangesStateToConfirming() {
        service.triggerEmergency()
        XCTAssertEqual(service.state, .confirming)
    }

    func testConfirmChangesStateToAlerted() {
        service.triggerEmergency()
        service.confirmEmergency()
        XCTAssertEqual(service.state, .alerted)
    }

    func testCancelReturnsToInactive() {
        service.triggerEmergency()
        service.cancelEmergency()
        XCTAssertEqual(service.state, .inactive)
    }

    func testConfirmationMessage() {
        let message = service.confirmationMessage(caregiverName: "Sarah")
        XCTAssertTrue(message.contains("Sarah"))
        XCTAssertTrue(message.contains("contact"))
    }

    func testConfirmationMessageWithoutCaregiver() {
        let message = service.confirmationMessage(caregiverName: nil)
        XCTAssertTrue(message.contains("emergency contact"))
    }

    // MARK: - Timeout

    func testTimeoutDuration() {
        XCTAssertEqual(EmergencyService.confirmationTimeoutSeconds, 15)
    }
}
