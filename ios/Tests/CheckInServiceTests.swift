import XCTest

// MARK: - Mock Companion Provider (shared across test files)

final class MockCompanionProvider: CompanionProvider {
    var responseToReturn: String = "Hello! How are you feeling today?"
    var extractionToReturn: String = "{}"
    var generateCallCount: Int = 0
    var extractCallCount: Int = 0
    var lastSystemPrompt: String?
    var lastMessages: [CompanionMessage] = []

    /// Alias used by IntentRecoveryServiceTests
    var nextResponse: String {
        get { responseToReturn }
        set { responseToReturn = newValue }
    }
    /// Alias used by IntentRecoveryServiceTests
    var nextExtraction: String {
        get { extractionToReturn }
        set { extractionToReturn = newValue }
    }

    func generateResponse(
        messages: [CompanionMessage],
        systemPrompt: String,
        temperature: Double
    ) async throws -> String {
        generateCallCount += 1
        lastSystemPrompt = systemPrompt
        lastMessages = messages
        return responseToReturn
    }

    func extractHealthData(
        conversationText: String,
        extractionPrompt: String
    ) async throws -> String {
        extractCallCount += 1
        return extractionToReturn
    }
}

// MARK: - Mock Gemini Service

/// Overrides sendStructuredRequest to return controlled extraction JSON
/// instead of hitting the real Gemini API.
final class MockGeminiService: GeminiService {
    var structuredResponseToReturn: [String: Any] = [:]
    var structuredCallCount: Int = 0

    override func sendStructuredRequest(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) async throws -> [String: Any] {
        structuredCallCount += 1
        return structuredResponseToReturn
    }
}

// MARK: - Tests

final class CheckInServiceTests: XCTestCase {

    private var mockProvider: MockCompanionProvider!
    private var mockGemini: MockGeminiService!
    private var service: CheckInService!

    override func setUp() {
        super.setUp()
        mockProvider = MockCompanionProvider()
        mockGemini = MockGeminiService()
        service = CheckInService(
            provider: mockProvider,
            geminiService: mockGemini,
            storageService: nil, // no Firestore in tests
            userId: "test-user",
            maxFollowUps: 3,
            companionName: "Mira"
        )
    }

    // MARK: - Start Check-In

    func testStartCheckInTransitionsToOpenResponse() async throws {
        let greeting = try await service.startCheckIn(type: .morning)

        XCTAssertFalse(greeting.isEmpty)
        XCTAssertEqual(service.state, .openResponse)
        XCTAssertNotNil(service.currentCheckIn)
        XCTAssertEqual(service.currentCheckIn?.type, .morning)
        XCTAssertEqual(service.currentCheckIn?.completionStatus, .inProgress)
    }

    func testStartCheckInCreatesTranscript() async throws {
        _ = try await service.startCheckIn(type: .evening)

        XCTAssertNotNil(service.transcript)
        XCTAssertEqual(service.transcript?.entries.count, 1) // greeting
        XCTAssertEqual(service.transcript?.entries.first?.role, .assistant)
    }

    func testStartCheckInFailsWhenAlreadyActive() async throws {
        _ = try await service.startCheckIn(type: .morning)

        do {
            _ = try await service.startCheckIn(type: .evening)
            XCTFail("Expected alreadyActive error")
        } catch let error as CheckInService.CheckInServiceError {
            XCTAssertEqual(error, .alreadyActive)
        }
    }

    // MARK: - Process Input

    func testProcessInputTriggersExtraction() async throws {
        // Setup extraction response with uncovered topics → drives follow-up
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "positive",
            "moodDetail": "feeling good",
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "ask",
            "topicsCovered": ["mood"],
            "topicsNotYetCovered": ["sleep", "symptoms"]
        ]

        _ = try await service.startCheckIn(type: .morning)
        let response = try await service.processUserInput("I'm feeling pretty good today")

        XCTAssertFalse(response.isEmpty)
        XCTAssertEqual(mockGemini.structuredCallCount, 1)
    }

    func testProcessInputRecordsInTranscript() async throws {
        _ = try await service.startCheckIn(type: .morning)
        _ = try await service.processUserInput("I'm feeling good")

        XCTAssertNotNil(service.transcript)
        // greeting + user input + assistant response = 3
        XCTAssertEqual(service.transcript?.entries.count, 3)
        XCTAssertEqual(service.transcript?.entries[1].role, .user)
        XCTAssertEqual(service.transcript?.entries[1].text, "I'm feeling good")
    }

    // MARK: - Follow-Ups

    func testFollowUpsLimitedToMax() async throws {
        // Each extraction returns uncovered topics
        mockGemini.structuredResponseToReturn = [
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "ask",
            "topicsCovered": ["mood"],
            "topicsNotYetCovered": ["sleep", "symptoms", "medication"]
        ]

        _ = try await service.startCheckIn(type: .morning)

        // Process inputs up to maxFollowUps (3)
        for i in 0..<3 {
            _ = try await service.processUserInput("Response \(i)")
        }

        XCTAssertEqual(service.followUpCount, 3)
    }

    // MARK: - Cancel

    func testCancelSetsAbandonedStatus() async throws {
        _ = try await service.startCheckIn(type: .morning)
        XCTAssertEqual(service.state, .openResponse)

        await service.cancelCheckIn()

        XCTAssertEqual(service.state, .idle)
        XCTAssertNil(service.currentCheckIn)
    }

    func testCancelOnIdleIsNoOp() async {
        await service.cancelCheckIn()
        XCTAssertEqual(service.state, .idle)
    }

    // MARK: - Provider Calls

    func testGenerateResponseCalledWithSystemPrompt() async throws {
        _ = try await service.startCheckIn(type: .morning)

        XCTAssertNotNil(mockProvider.lastSystemPrompt)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("Mira") == true)
    }

    // MARK: - Extraction Application

    func testExtractionAppliesMoodToCheckIn() async throws {
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "positive",
            "moodDetail": "feeling great",
            "moodScore": 4,
            "emotion": "happy",
            "engagementLevel": "high",
            "recommendedAction": "affirm",
            "topicsCovered": ["mood", "sleep", "symptoms", "medication"],
            "topicsNotYetCovered": [] as [String]
        ]

        _ = try await service.startCheckIn(type: .morning)
        _ = try await service.processUserInput("I'm feeling great today, slept well")

        XCTAssertNotNil(service.currentCheckIn?.mood)
        XCTAssertEqual(service.currentCheckIn?.mood?.label, "positive")
        XCTAssertEqual(service.currentCheckIn?.mood?.description, "feeling great")
    }

    // MARK: - Action-Based Dispatch

    func testReflectActionTriggersReflection() async throws {
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "negative",
            "moodDetail": "my hands were really shaky",
            "emotion": "frustrated",
            "engagementLevel": "high",
            "recommendedAction": "reflect",
            "topicsCovered": ["symptoms"],
            "topicsNotYetCovered": ["mood", "sleep", "medication"]
        ]
        mockProvider.responseToReturn = "That sounds really frustrating."

        _ = try await service.startCheckIn(type: .morning)
        let response = try await service.processUserInput("My hands were really shaky and I couldn't button my shirt")

        XCTAssertEqual(response, "That sounds really frustrating.")
        XCTAssertEqual(service.state, .followUp)
    }

    func testAffirmActionTriggersAffirmation() async throws {
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "positive",
            "moodDetail": "slept really well",
            "emotion": "happy",
            "engagementLevel": "high",
            "recommendedAction": "affirm",
            "topicsCovered": ["sleep"],
            "topicsNotYetCovered": ["mood", "symptoms", "medication"]
        ]
        mockProvider.responseToReturn = "That's wonderful that you got good rest!"

        _ = try await service.startCheckIn(type: .morning)
        let response = try await service.processUserInput("I actually slept really well last night")

        XCTAssertEqual(response, "That's wonderful that you got good rest!")
        XCTAssertEqual(service.state, .followUp)
    }

    func testSummarizeActionTriggersMidSummary() async throws {
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "positive",
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "summarize",
            "topicsCovered": ["mood", "sleep", "symptoms"],
            "topicsNotYetCovered": ["medication"]
        ]

        _ = try await service.startCheckIn(type: .morning)
        _ = try await service.processUserInput("Yeah the stiffness was mild today")

        XCTAssertEqual(service.state, .followUp)
    }

    func testCloseActionSkipsToConfirming() async throws {
        mockGemini.structuredResponseToReturn = [
            "emotion": "tired",
            "engagementLevel": "low",
            "recommendedAction": "close",
            "topicsCovered": ["mood"],
            "topicsNotYetCovered": ["sleep", "symptoms", "medication"]
        ]

        _ = try await service.startCheckIn(type: .morning)
        _ = try await service.processUserInput("yeah")

        XCTAssertEqual(service.state, .confirming)
    }

    func testNilActionDefaultsToAsk() async throws {
        // No guidance fields → acts like "ask"
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "positive",
            "topicsCovered": ["mood"],
            "topicsNotYetCovered": ["sleep", "symptoms"]
        ]

        _ = try await service.startCheckIn(type: .morning)
        _ = try await service.processUserInput("I'm feeling good today")

        // Should follow up (ask behavior) since topics remain
        XCTAssertEqual(service.state, .followUp)
    }

    func testEmotionFallbackReflectsOnDistress() async throws {
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "negative",
            "emotion": "in_pain",
            "engagementLevel": "medium",
            "recommendedAction": "unknown_action",
            "topicsCovered": ["symptoms"],
            "topicsNotYetCovered": ["mood", "sleep", "medication"]
        ]

        _ = try await service.startCheckIn(type: .morning)
        _ = try await service.processUserInput("Everything hurts today")

        // Unknown action + distressed emotion → reflect fallback
        XCTAssertEqual(service.state, .followUp)
    }

    // MARK: - State Machine

    func testStateTransitionsForFullFlow() async throws {
        // All topics covered → skips follow-ups → goes to confirming
        mockGemini.structuredResponseToReturn = [
            "moodLabel": "positive",
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "ask",
            "topicsCovered": ["mood", "sleep", "symptoms", "medication"],
            "topicsNotYetCovered": [] as [String]
        ]

        XCTAssertEqual(service.state, .idle)

        _ = try await service.startCheckIn(type: .morning)
        XCTAssertEqual(service.state, .openResponse)

        _ = try await service.processUserInput("I'm doing well, slept great, no issues, took my meds")
        // Should go to confirming since all topics covered
        XCTAssertEqual(service.state, .confirming)
    }
}

// MARK: - Equatable for Error Matching

extension CheckInService.CheckInServiceError: Equatable {
    static func == (lhs: CheckInService.CheckInServiceError, rhs: CheckInService.CheckInServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.alreadyActive, .alreadyActive): return true
        case (.notActive, .notActive): return true
        default: return false
        }
    }
}
