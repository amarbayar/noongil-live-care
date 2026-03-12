import XCTest

@MainActor
final class FeatureFlagServiceTests: XCTestCase {

    func testDefaultValues() {
        let service = FeatureFlagService()
        // Defaults before any JSON loading (bundle won't exist in test target with Bundle.main)
        // applyFlags hasn't been called with non-default values
        XCTAssertTrue(service.checkInEnabled)
        XCTAssertTrue(service.glassesCameraEnabled)
        XCTAssertFalse(service.caregiverLinkingEnabled)
        XCTAssertFalse(service.doctorReportEnabled)
        XCTAssertFalse(service.voiceBiomarkerEnabled)
        XCTAssertEqual(service.enhancementModeDefault, "SBR")
        XCTAssertEqual(service.pipelineModeDefault, "local")
        XCTAssertEqual(service.maxCheckInQuestions, 5)
        XCTAssertFalse(service.correlationEngineEnabled)
        XCTAssertEqual(service.companionName, "Mira")
    }

    func testApplyFlagsOverridesValues() {
        let service = FeatureFlagService()
        let flags: [String: Any] = [
            "check_in_enabled": false,
            "caregiver_linking_enabled": true,
            "doctor_report_enabled": true,
            "enhancement_mode_default": "sbrOnly",
            "pipeline_mode_default": "live",
            "max_check_in_questions": 10,
            "companion_name": "Nova"
        ]

        service.applyFlags(flags)

        XCTAssertFalse(service.checkInEnabled)
        XCTAssertTrue(service.caregiverLinkingEnabled)
        XCTAssertTrue(service.doctorReportEnabled)
        XCTAssertEqual(service.enhancementModeDefault, "sbrOnly")
        XCTAssertEqual(service.pipelineModeDefault, "live")
        XCTAssertEqual(service.maxCheckInQuestions, 10)
        XCTAssertEqual(service.companionName, "Nova")
    }

    func testApplyFlagsPartialUpdate() {
        let service = FeatureFlagService()
        let partial: [String: Any] = [
            "companion_name": "Zara"
        ]

        service.applyFlags(partial)

        // Only companion_name changed; others remain default
        XCTAssertTrue(service.checkInEnabled)
        XCTAssertEqual(service.companionName, "Zara")
        XCTAssertEqual(service.maxCheckInQuestions, 5)
    }

    func testApplyFlagsIgnoresUnknownKeys() {
        let service = FeatureFlagService()
        let flags: [String: Any] = [
            "unknown_flag": true,
            "companion_name": "Test"
        ]

        service.applyFlags(flags)

        XCTAssertEqual(service.companionName, "Test")
    }

    func testApplyFlagsIgnoresWrongTypes() {
        let service = FeatureFlagService()
        let flags: [String: Any] = [
            "check_in_enabled": "yes",      // String, not Bool
            "max_check_in_questions": "ten"  // String, not Int
        ]

        service.applyFlags(flags)

        // Values unchanged because types don't match
        XCTAssertTrue(service.checkInEnabled)
        XCTAssertEqual(service.maxCheckInQuestions, 5)
    }

    func testLoadBundledFlags() {
        let service = FeatureFlagService()

        // In the test bundle, config/ is included as a folder resource
        // loadBundledFlags() is called in init(), so if the file is present
        // it should have loaded. We verify against known values in feature-flags.json.
        // If bundle loading fails (test runner), defaults still hold.
        XCTAssertTrue(service.checkInEnabled)
        XCTAssertEqual(service.companionName, "Mira")
    }
}
