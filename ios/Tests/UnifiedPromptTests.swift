import XCTest

final class UnifiedPromptTests: XCTestCase {

    func testUnifiedPromptLoads() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertFalse(prompt.isEmpty, "Unified system prompt should load")
    }

    func testUnifiedPromptContainsMemoryPlaceholder() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertTrue(prompt.contains("{MEMORY_CONTEXT}"),
            "Unified prompt must contain {MEMORY_CONTEXT} placeholder for memory injection")
    }

    func testUnifiedPromptContainsSessionContextPlaceholder() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertTrue(prompt.contains("{SESSION_CONTEXT}"),
            "Unified prompt must contain {SESSION_CONTEXT} placeholder for device-local time injection")
    }

    func testUnifiedPromptContainsCompanionNamePlaceholder() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertTrue(prompt.contains("{COMPANION_NAME}"),
            "Unified prompt must contain {COMPANION_NAME} placeholder")
    }

    func testUnifiedPromptContainsAgencyRules() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertTrue(prompt.contains("wrap up"), "Should mention 'wrap up' as agency signal")
        XCTAssertTrue(prompt.contains("stop"), "Should mention 'stop' as agency signal")
        XCTAssertTrue(prompt.contains("done"), "Should mention 'done' as agency signal")
        XCTAssertTrue(prompt.contains("complete_session"), "Should reference complete_session tool")
    }

    func testUnifiedPromptContainsGetGuidance() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertTrue(prompt.contains("get_guidance"),
            "Unified prompt must instruct model to call get_guidance")
    }

    func testUnifiedPromptContainsRecentRecallInstructions() {
        let prompt = PromptService.unifiedSystemPrompt
        XCTAssertTrue(prompt.contains("Earlier you mentioned") || prompt.contains("recently mentioned"),
            "Unified prompt should explain how to answer recent recall questions from memory")
    }

    func testUnifiedPromptDoesNotContainClinicalLanguage() {
        let prompt = PromptService.unifiedSystemPrompt
        // The prompt should warn against clinical language, not use it clinically
        XCTAssertFalse(prompt.contains("diagnosis"))
        XCTAssertFalse(prompt.contains("prognosis"))
    }

    func testContextInjection_producesValidPrompt() {
        let prompt = PromptService.unifiedSystemPrompt

        // Simulate memory context
        let memoryContext = """
        [Who You're Talking To]
        Name: John
        Week 3 of check-ins

        [Recent Sessions]
        - 2 min ago: Discussed morning tremor improvement (feeling hopeful)
        - Yesterday: Talked about sleep patterns and medication adherence

        [What You Know About Them]
        - [sleep] Usually sleeps 6 hours (confidence: 80%)
        - [preference] Prefers tea before bed (confidence: 70%)

        [How To Behave]
        - When user says stop: respect immediately, transition to close

        [Right Now]
        Current time: Tuesday, 9:15 AM
        """

        let sessionContext = """
        [Session Context]
        Today (local device date): Friday, March 6, 2026
        Tomorrow (local device date): Saturday, March 7, 2026
        Current local time: 9:15 AM
        Current timezone: America/Los_Angeles (PST)
        Current locale: en_US
        """

        let injected = prompt
            .replacingOccurrences(of: "{MEMORY_CONTEXT}", with: memoryContext)
            .replacingOccurrences(of: "{SESSION_CONTEXT}", with: sessionContext)
            .replacingOccurrences(of: "{COMPANION_NAME}", with: "Mira")

        let tokens = MemoryBudget.estimateTokens(injected)
        XCTAssertLessThan(tokens, 8000, "Injected prompt should be under 8k tokens, got \(tokens)")
        XCTAssertTrue(injected.contains("John"))
        XCTAssertTrue(injected.contains("tremor improvement"))
        XCTAssertTrue(injected.contains("Mira"))
        XCTAssertTrue(injected.contains("Friday, March 6, 2026"))
        XCTAssertFalse(injected.contains("{MEMORY_CONTEXT}"), "Placeholder should be replaced")
        XCTAssertFalse(injected.contains("{SESSION_CONTEXT}"), "Placeholder should be replaced")
        XCTAssertFalse(injected.contains("{COMPANION_NAME}"), "Placeholder should be replaced")
    }

    func testBuildSessionContext_includesCurrentDateTimeAndTimezone() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 3,
            day: 6,
            hour: 21,
            minute: 15
        ))!

        let context = PromptService.buildSessionContext(
            date: date,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(context.contains("Friday, March 6, 2026"))
        XCTAssertTrue(context.contains("Saturday, March 7, 2026"))
        XCTAssertTrue(context.contains("Current local time: 9:15 PM"))
        XCTAssertTrue(context.contains("Current timezone: America/Los_Angeles"))
        XCTAssertTrue(context.contains("Current locale: en_US"))
        XCTAssertTrue(context.contains("today"))
        XCTAssertTrue(context.contains("tomorrow"))
    }

    func testRenderUnifiedSystemPrompt_replacesSessionContextPlaceholder() {
        let rendered = PromptService.renderUnifiedSystemPrompt(
            companionName: "Mira",
            memoryContext: "[Right Now]\nCurrent time: Tuesday, 9:15 AM",
            sessionContext: """
            [Session Context]
            Today (local device date): Friday, March 6, 2026
            """
        )

        XCTAssertTrue(rendered.contains("Friday, March 6, 2026"))
        XCTAssertFalse(rendered.contains("{SESSION_CONTEXT}"))
        XCTAssertFalse(rendered.contains("{MEMORY_CONTEXT}"))
        XCTAssertFalse(rendered.contains("{COMPANION_NAME}"))
    }
}
