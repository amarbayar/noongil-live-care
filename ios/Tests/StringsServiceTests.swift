import XCTest

@MainActor
final class StringsServiceTests: XCTestCase {

    func testSubscriptReturnKeyWhenMissing() {
        let service = StringsService()
        // If bundle loading fails, strings dict is empty
        // Subscript should return the key itself as fallback
        service.strings = [:]
        XCTAssertEqual(service["nonexistent_key"], "nonexistent_key")
    }

    func testSubscriptReturnsValue() {
        let service = StringsService()
        service.strings = ["greeting_morning": "Good morning!"]
        XCTAssertEqual(service["greeting_morning"], "Good morning!")
    }

    func testLocalizedInterpolation() {
        let service = StringsService()
        service.strings = ["medication_reminder": "Time for your %medication%. Did you take it?"]

        let result = service.localized("medication_reminder", variables: ["medication": "Aspirin"])
        XCTAssertEqual(result, "Time for your Aspirin. Did you take it?")
    }

    func testLocalizedMultipleVariables() {
        let service = StringsService()
        service.strings = ["greeting": "Hello %name%, your score is %score%"]

        let result = service.localized("greeting", variables: ["name": "Amar", "score": "100"])
        XCTAssertEqual(result, "Hello Amar, your score is 100")
    }

    func testLocalizedNoVariables() {
        let service = StringsService()
        service.strings = ["checkin_start": "Let's do a quick check-in."]

        let result = service.localized("checkin_start")
        XCTAssertEqual(result, "Let's do a quick check-in.")
    }

    func testLocalizedMissingKeyReturnsKey() {
        let service = StringsService()
        service.strings = [:]

        let result = service.localized("missing_key", variables: ["x": "y"])
        XCTAssertEqual(result, "missing_key")
    }

    func testDefaultLanguageIsEnglish() {
        let service = StringsService()
        XCTAssertEqual(service.currentLanguage, "en")
    }

    func testSwitchLanguageSameLanguageNoOp() {
        let service = StringsService()
        service.strings = ["test": "value"]
        service.switchLanguage("en")
        // Should not reset strings (same language)
        XCTAssertEqual(service["test"], "value")
    }
}
