import XCTest

@MainActor
final class ConsentServiceTests: XCTestCase {

    private func makeService() -> ConsentService {
        let defaults = UserDefaults(suiteName: "test-consent-\(UUID().uuidString)")!
        return ConsentService(defaults: defaults)
    }

    func testAllConsentsInitiallyFalse() {
        let sut = makeService()
        XCTAssertFalse(sut.healthDataConsent)
        XCTAssertFalse(sut.aiAnalysisConsent)
        XCTAssertFalse(sut.voiceProcessingConsent)
        XCTAssertFalse(sut.termsAccepted)
        XCTAssertFalse(sut.privacyPolicyAccepted)
        XCTAssertFalse(sut.ageConfirmed)
        XCTAssertFalse(sut.allConsentsGranted)
    }

    func testAllConsentsGrantedRequiresAll() {
        let sut = makeService()
        sut.healthDataConsent = true
        sut.aiAnalysisConsent = true
        sut.voiceProcessingConsent = true
        sut.termsAccepted = true
        sut.privacyPolicyAccepted = true
        // Missing ageConfirmed
        XCTAssertFalse(sut.allConsentsGranted)

        sut.ageConfirmed = true
        XCTAssertTrue(sut.allConsentsGranted)
    }

    func testGrantAll() {
        let sut = makeService()
        sut.grantAll()
        XCTAssertTrue(sut.allConsentsGranted)
    }

    func testRevokeAll() {
        let sut = makeService()
        sut.grantAll()
        XCTAssertTrue(sut.allConsentsGranted)

        sut.revokeAll()
        XCTAssertFalse(sut.allConsentsGranted)
        XCTAssertFalse(sut.healthDataConsent)
    }

    func testPersistence() {
        let suiteName = "test-consent-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Grant via first instance
        let sut1 = ConsentService(defaults: defaults)
        sut1.grantAll()

        // Load via second instance using same defaults
        let sut2 = ConsentService(defaults: defaults)
        XCTAssertTrue(sut2.allConsentsGranted)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRevokingSingleConsentBreaksAll() {
        let sut = makeService()
        sut.grantAll()
        XCTAssertTrue(sut.allConsentsGranted)

        sut.voiceProcessingConsent = false
        XCTAssertFalse(sut.allConsentsGranted)
    }
}
