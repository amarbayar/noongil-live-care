import XCTest

final class PromptServiceTests: XCTestCase {

    func testCompanionSystemPromptIsNotEmpty() {
        let prompt = PromptService.companionSystemPrompt
        XCTAssertFalse(prompt.isEmpty)
    }

    func testCompanionSystemPromptContainsMira() {
        // Whether loaded from bundle or fallback, prompt should mention Mira
        let prompt = PromptService.companionSystemPrompt
        XCTAssertTrue(prompt.contains("Mira"), "System prompt should contain companion name 'Mira'")
    }

    func testCompanionSystemPromptContainsWellnessLanguage() {
        let prompt = PromptService.companionSystemPrompt
        XCTAssertTrue(prompt.contains("wellness") || prompt.contains("companion"),
                       "System prompt should use wellness/companion language, not clinical")
    }

    func testCompanionSystemPromptDoesNotContainClinicalLanguage() {
        let prompt = PromptService.companionSystemPrompt
        XCTAssertFalse(prompt.contains("patient"), "System prompt must not use 'patient'")
        XCTAssertFalse(prompt.contains("diagnosis"), "System prompt must not use 'diagnosis'")
    }
}
