import XCTest

final class IntentRecoveryServiceTests: XCTestCase {

    private var mockProvider: MockCompanionProvider!
    private var service: IntentRecoveryService!

    override func setUp() {
        super.setUp()
        mockProvider = MockCompanionProvider()
        service = IntentRecoveryService(provider: mockProvider, confidenceThreshold: 0.4)
    }

    // MARK: - Should Attempt Recovery

    func testEmptyTextNeedsRecovery() {
        XCTAssertTrue(service.shouldAttemptRecovery(text: "", audioDurationSeconds: 3.0))
    }

    func testWhitespaceOnlyNeedsRecovery() {
        XCTAssertTrue(service.shouldAttemptRecovery(text: "   ", audioDurationSeconds: 2.0))
    }

    func testVeryShortTextWithLongAudioNeedsRecovery() {
        // 5 seconds of audio but only 1 word — likely garbled
        XCTAssertTrue(service.shouldAttemptRecovery(text: "uh", audioDurationSeconds: 5.0))
    }

    func testReasonableTextDoesNotNeedRecovery() {
        XCTAssertFalse(service.shouldAttemptRecovery(text: "I slept pretty well last night", audioDurationSeconds: 3.0))
    }

    func testShortButQuickResponseDoesNotNeedRecovery() {
        // Short text from short audio is fine (e.g., "yes")
        XCTAssertFalse(service.shouldAttemptRecovery(text: "yes", audioDurationSeconds: 0.8))
    }

    func testSingleCharWithModerateAudioNeedsRecovery() {
        XCTAssertTrue(service.shouldAttemptRecovery(text: "a", audioDurationSeconds: 3.0))
    }

    // MARK: - Recover Intent

    func testRecoverIntentReturnsProviderResponse() async throws {
        mockProvider.nextResponse = "The user said their tremor is worse today."

        let result = try await service.recoverIntent(
            garbledText: "trmr wrs",
            conversationContext: "Asking about symptoms",
            accommodationLevel: .moderate
        )

        XCTAssertEqual(result, "The user said their tremor is worse today.")
    }

    func testRecoverIntentIncludesContextInPrompt() async throws {
        mockProvider.nextResponse = "Recovered text."

        _ = try await service.recoverIntent(
            garbledText: "leva dope tkn",
            conversationContext: "Asking about medication",
            accommodationLevel: .severe
        )

        // Verify the provider received context about speech impairment
        let lastMessages = mockProvider.lastMessages
        XCTAssertFalse(lastMessages.isEmpty)
        let systemContent = lastMessages.first { $0.role == .system }?.content ?? ""
        XCTAssertTrue(systemContent.contains("speech"))
    }

    func testRecoverIntentIncludesGarbledText() async throws {
        mockProvider.nextResponse = "Recovered."

        _ = try await service.recoverIntent(
            garbledText: "shky hnd",
            conversationContext: "Asking about tremor",
            accommodationLevel: .mild
        )

        let userContent = mockProvider.lastMessages.first { $0.role == .user }?.content ?? ""
        XCTAssertTrue(userContent.contains("shky hnd"))
    }
}

// MockCompanionProvider is defined in CheckInServiceTests.swift (shared)
