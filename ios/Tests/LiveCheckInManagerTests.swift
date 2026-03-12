import XCTest

@MainActor
final class LiveCheckInManagerTests: XCTestCase {

    private var manager: LiveCheckInManager!

    override func setUp() {
        super.setUp()
        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            userId: "test-user",
            companionName: "Mira"
        )
    }

    // MARK: - Start

    func testStartActivatesManager() async throws {
        let prompt = try await manager.start(type: .adhoc)

        XCTAssertTrue(manager.isActive)
        XCTAssertFalse(prompt.isEmpty)
    }

    func testStartPromptContainsCheckInInstructions() async throws {
        let prompt = try await manager.start(type: .morning)

        XCTAssertTrue(prompt.contains("get_check_in_guidance"))
        XCTAssertTrue(prompt.contains("complete_check_in"))
    }

    func testStartPromptContainsContext() async throws {
        let prompt = try await manager.start(type: .adhoc)

        // Should contain companion name from context
        XCTAssertTrue(prompt.contains("Mira"))
    }

    func testStartPromptContainsGreetingContext() async throws {
        let prompt = try await manager.start(type: .morning)

        // Should reference the check-in type
        XCTAssertTrue(prompt.contains("morning"))
    }

    func testStartFailsWhenAlreadyActive() async throws {
        _ = try await manager.start(type: .adhoc)

        do {
            _ = try await manager.start(type: .adhoc)
            XCTFail("Expected alreadyActive error")
        } catch let error as LiveCheckInManager.LiveCheckInError {
            XCTAssertEqual(error, .alreadyActive)
        }
    }

    // MARK: - Transcript Accumulation

    func testAddUserTranscript() async throws {
        _ = try await manager.start(type: .adhoc)

        manager.addUserTranscript("I'm feeling pretty good today")
        manager.addUserTranscript("Slept about seven hours")

        // Guidance should reflect accumulated transcript (tested indirectly via handleGetGuidance)
        XCTAssertTrue(manager.isActive)
    }

    func testAddAssistantTranscript() async throws {
        _ = try await manager.start(type: .adhoc)

        manager.addAssistantTranscript("Good morning! How are you feeling?")

        XCTAssertTrue(manager.isActive)
    }

    func testTranscriptIgnoredWhenInactive() {
        // Should not crash when adding transcript to inactive manager
        manager.addUserTranscript("Hello")
        manager.addAssistantTranscript("Hi")
        XCTAssertFalse(manager.isActive)
    }

    func testEmptyTranscriptIgnored() async throws {
        _ = try await manager.start(type: .adhoc)

        manager.addUserTranscript("")
        manager.addAssistantTranscript("")

        XCTAssertTrue(manager.isActive)
    }

    // MARK: - Guidance

    func testHandleGetGuidanceReturnsExpectedFields() async throws {
        _ = try await manager.start(type: .adhoc)
        manager.addUserTranscript("I'm feeling good today")

        // Note: This calls Gemini REST for extraction which will fail in tests without network.
        // The method handles extraction failure gracefully and returns default guidance.
        let guidance = await manager.handleGetGuidance()

        // Should always have these fields
        XCTAssertNotNil(guidance["topicsCovered"])
        XCTAssertNotNil(guidance["topicsRemaining"])
        XCTAssertNotNil(guidance["activeMedications"])
        XCTAssertNotNil(guidance["emotion"])
        XCTAssertNotNil(guidance["engagementLevel"])
        XCTAssertNotNil(guidance["recommendedAction"])
        XCTAssertNotNil(guidance["nextTopicHint"])
        XCTAssertNotNil(guidance["instruction"])
    }

    func testHandleGetGuidanceDefaultsWhenExtractionFails() async throws {
        _ = try await manager.start(type: .adhoc)

        // No transcript → extraction will have no data → defaults
        let guidance = await manager.handleGetGuidance()

        XCTAssertEqual(guidance["emotion"] as? String, "calm")
        XCTAssertEqual(guidance["engagementLevel"] as? String, "medium")
        XCTAssertEqual(guidance["recommendedAction"] as? String, "ask")
    }

    func testHandleGetGuidanceReturnsErrorWhenInactive() async {
        let guidance = await manager.handleGetGuidance()

        XCTAssertNotNil(guidance["error"])
    }

    func testHandleGetGuidanceDefaultTopicsRemaining() async throws {
        _ = try await manager.start(type: .adhoc)

        let guidance = await manager.handleGetGuidance()

        // Without successful extraction, uncoveredTopics stays at default
        let remaining = guidance["topicsRemaining"] as? [String] ?? []
        XCTAssertTrue(remaining.contains("mood"))
        XCTAssertTrue(remaining.contains("sleep"))
        XCTAssertTrue(remaining.contains("symptoms"))
        XCTAssertTrue(remaining.contains("medication"))
    }

    func testHandleGetGuidance_greetingOverridesFalseCloseExtraction() async throws {
        let mockGemini = MockLiveGuidanceGeminiService()
        mockGemini.structuredResponseToReturn = [
            "emotion": "calm",
            "engagementLevel": "low",
            "recommendedAction": "close",
            "userWantsToEnd": true,
            "topicsCovered": [],
            "topicsNotYetCovered": ["mood", "sleep", "symptoms", "medication"]
        ]
        manager = LiveCheckInManager(
            geminiService: mockGemini,
            storageService: nil,
            graphSyncService: nil,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)
        manager.addUserTranscript("hello?")

        let guidance = await manager.handleGetGuidance()

        XCTAssertEqual(guidance["recommendedAction"] as? String, "ask")
        XCTAssertEqual(guidance["instruction"] as? String, "Greet them warmly, then begin by asking about mood.")
    }

    // MARK: - Complete

    func testHandleCompleteMarksCompleted() async throws {
        _ = try await manager.start(type: .adhoc)

        let result = await manager.handleComplete()

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertFalse(manager.isActive)
    }

    func testHandleCompleteReturnsDuration() async throws {
        _ = try await manager.start(type: .adhoc)

        // Small delay to ensure durationSeconds > 0
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        let result = await manager.handleComplete()

        XCTAssertNotNil(result["durationSeconds"])
    }

    func testHandleCompleteCallsOnComplete() async throws {
        _ = try await manager.start(type: .adhoc)

        var completeCalled = false
        manager.onComplete = { completeCalled = true }

        _ = await manager.handleComplete()

        XCTAssertTrue(completeCalled)
    }

    func testHandleCompleteFailsWhenInactive() async {
        let result = await manager.handleComplete()

        XCTAssertEqual(result["success"] as? Bool, false)
    }

    func testHandleCompleteIsIdempotent() async throws {
        let storage = MockLiveCheckInStore()
        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)

        let first = await manager.handleComplete()
        let second = await manager.handleComplete()

        XCTAssertEqual(first["success"] as? Bool, true)
        XCTAssertEqual(second["success"] as? Bool, true)
        XCTAssertEqual(storage.completedCheckInSaves, 1, "Terminal completion should only be persisted once")
    }

    // MARK: - Cancel

    func testCancelDeactivatesManager() async throws {
        _ = try await manager.start(type: .adhoc)
        XCTAssertTrue(manager.isActive)

        manager.cancel()

        XCTAssertFalse(manager.isActive)
    }

    func testCancelOnInactiveIsNoOp() {
        manager.cancel()
        XCTAssertFalse(manager.isActive)
    }

    // MARK: - Tool Declarations

    func testCheckInToolDeclarationsHasExpectedTools() {
        let tools = LiveCheckInManager.checkInToolDeclarations

        XCTAssertEqual(tools.count, 2)

        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("get_check_in_guidance"))
        XCTAssertTrue(names.contains("complete_check_in"))
    }

    func testCheckInToolDeclarationsHaveDescriptions() {
        for tool in LiveCheckInManager.checkInToolDeclarations {
            XCTAssertNotNil(tool["description"], "Tool \(tool["name"] ?? "?") missing description")
            XCTAssertNotNil(tool["parameters"], "Tool \(tool["name"] ?? "?") missing parameters")
        }
    }

    // MARK: - Session Durability

    func testTranscriptPersistsEachTurn() async throws {
        let storage = MockLiveCheckInStore()
        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)
        manager.addUserTranscript("I slept okay")
        manager.addAssistantTranscript("Thanks for sharing that.")
        await manager.waitForPendingPersistence()

        XCTAssertEqual(storage.savedTranscript?.entryCount, 2)
        XCTAssertEqual(storage.savedTranscript?.entries.first?.role, .user)
        XCTAssertEqual(storage.savedTranscript?.entries.last?.role, .assistant)
    }

    func testTranscriptEventsAppendInOrder() async throws {
        let storage = MockLiveCheckInStore()
        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)
        manager.addUserTranscript("I slept okay")
        manager.addAssistantTranscript("Thanks for sharing that.")
        await manager.waitForPendingPersistence()

        XCTAssertEqual(
            storage.savedSessionEvents.map(\.type),
            [.sessionStarted, .userUtterance, .assistantUtterance]
        )
        XCTAssertEqual(
            storage.savedSessionEvents.map(\.sequenceNumber),
            [0, 1, 2]
        )
    }

    func testFinalizePendingTranscriptTurnAppendsFinalUpsertedUtterances() async throws {
        let storage = MockLiveCheckInStore()
        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)
        manager.upsertUserTranscript("I slept")
        manager.upsertUserTranscript("I slept okay")
        manager.upsertAssistantTranscript("Thanks")
        manager.upsertAssistantTranscript("Thanks for sharing that.")

        await manager.finalizePendingTranscriptTurn()
        await manager.waitForPendingPersistence()

        XCTAssertEqual(
            storage.savedSessionEvents.map(\.type),
            [.sessionStarted, .userUtterance, .assistantUtterance]
        )
        XCTAssertEqual(storage.savedSessionEvents[1].text, "I slept okay")
        XCTAssertEqual(storage.savedSessionEvents[2].text, "Thanks for sharing that.")
    }

    func testStartResumesInProgressCheckInAndTranscript() async throws {
        let storage = MockLiveCheckInStore()
        var existingCheckIn = CheckIn(userId: "test-user", type: .adhoc, pipelineMode: "live")
        existingCheckIn.id = "check-in-1"
        existingCheckIn.checkInNumber = 4
        storage.inProgressCheckIn = existingCheckIn

        var existingTranscript = Transcript(checkInId: "check-in-1")
        existingTranscript.addEntry(role: .user, text: "Yesterday was rough")
        existingTranscript.addEntry(role: .assistant, text: "I remember. Want to continue?")
        existingTranscript.id = "check-in-1"
        storage.savedTranscript = existingTranscript

        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)

        XCTAssertEqual(manager.activeCheckInId, "check-in-1")
        XCTAssertEqual(manager.transcriptEntryCount, 2)
        XCTAssertEqual(storage.startMode, .resumed)
    }

    func testStartRebuildsTranscriptFromSessionEventsWhenTranscriptMissing() async throws {
        let storage = MockLiveCheckInStore()
        var existingCheckIn = CheckIn(userId: "test-user", type: .adhoc, pipelineMode: "live")
        existingCheckIn.id = "check-in-1"
        existingCheckIn.checkInNumber = 4
        storage.inProgressCheckIn = existingCheckIn
        storage.savedSessionEvents = [
            CompanionSessionEvent(
                sessionId: "check-in-1",
                sequenceNumber: 0,
                type: .sessionStarted,
                source: "live",
                metadata: ["checkInType": CheckInType.adhoc.rawValue]
            ),
            CompanionSessionEvent(
                sessionId: "check-in-1",
                sequenceNumber: 1,
                type: .userUtterance,
                source: "live",
                text: "Yesterday was rough"
            ),
            CompanionSessionEvent(
                sessionId: "check-in-1",
                sequenceNumber: 2,
                type: .assistantUtterance,
                source: "live",
                text: "I remember. Want to continue?"
            )
        ]

        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)

        XCTAssertEqual(manager.activeCheckInId, "check-in-1")
        XCTAssertEqual(manager.transcriptEntryCount, 2)
        XCTAssertEqual(storage.startMode, .resumed)
    }

    func testHandleCompleteEnqueuesProjectionOutboxItemsOnce() async throws {
        let storage = MockLiveCheckInStore()
        manager = LiveCheckInManager(
            geminiService: GeminiService(),
            storageService: nil,
            graphSyncService: nil,
            sessionStore: storage,
            userId: "test-user",
            companionName: "Mira"
        )

        _ = try await manager.start(type: .adhoc)

        _ = await manager.handleComplete()
        _ = await manager.handleComplete()
        await manager.waitForPendingPersistence()

        XCTAssertEqual(storage.savedOutboxItems.count, 2)
        XCTAssertEqual(
            Set(storage.savedOutboxItems.map(\.kind)),
            Set([.memoryProjection, .graphSync])
        )
        let memoryOutbox = storage.savedOutboxItems.first { $0.kind == .memoryProjection }
        XCTAssertNotNil(memoryOutbox?.payloadJSON)
    }
}

// MARK: - Test Doubles

private final class MockLiveGuidanceGeminiService: GeminiService {
    var structuredResponseToReturn: [String: Any] = [:]

    override func sendStructuredRequest(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) async throws -> [String: Any] {
        structuredResponseToReturn
    }
}

@MainActor
private final class MockLiveCheckInStore: LiveCheckInSessionStore {
    var profile: UserProfile?
    var recentCheckIns: [CheckIn] = []
    var medications: [Medication] = []
    var vocabularyMap: VocabularyMap?
    var inProgressCheckIn: CheckIn?
    var savedCheckIn: CheckIn?
    var savedTranscript: Transcript?
    var savedVocabularyMap: VocabularyMap?
    var savedSessionEvents: [CompanionSessionEvent] = []
    var savedOutboxItems: [CompanionProjectionOutboxItem] = []
    var completedCheckInSaves = 0
    var startMode: LiveCheckInStartMode?

    func loadContext(userId: String) async throws -> LiveCheckInContext {
        LiveCheckInContext(
            profile: profile,
            recentCheckIns: recentCheckIns,
            medications: medications,
            vocabularyMap: vocabularyMap
        )
    }

    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn? {
        inProgressCheckIn
    }

    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript? {
        savedTranscript
    }

    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent] {
        savedSessionEvents.filter { $0.sessionId == sessionId }.sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    func save(checkIn: CheckIn, userId: String) async throws -> String {
        savedCheckIn = checkIn
        if checkIn.completionStatus == .completed {
            completedCheckInSaves += 1
        }
        return checkIn.id ?? "generated-check-in-id"
    }

    func save(transcript: Transcript, userId: String) async throws -> String {
        savedTranscript = transcript
        return transcript.id ?? transcript.checkInId
    }

    func save(vocabularyMap: VocabularyMap, userId: String) async throws -> String {
        savedVocabularyMap = vocabularyMap
        return "vocabulary"
    }

    func append(sessionEvent: CompanionSessionEvent, userId: String) async throws -> String {
        if let index = savedSessionEvents.firstIndex(where: { $0.documentId == sessionEvent.documentId }) {
            savedSessionEvents[index] = sessionEvent
        } else {
            savedSessionEvents.append(sessionEvent)
            savedSessionEvents.sort { $0.sequenceNumber < $1.sequenceNumber }
        }
        return sessionEvent.documentId
    }

    func save(outboxItem: CompanionProjectionOutboxItem, userId: String) async throws -> String {
        if let index = savedOutboxItems.firstIndex(where: { $0.documentId == outboxItem.documentId }) {
            savedOutboxItems[index] = outboxItem
        } else {
            savedOutboxItems.append(outboxItem)
        }
        return outboxItem.documentId
    }

    func markStartMode(_ mode: LiveCheckInStartMode) {
        startMode = mode
    }
}

// MARK: - Equatable for Error Matching

extension LiveCheckInManager.LiveCheckInError: Equatable {
    public static func == (lhs: LiveCheckInManager.LiveCheckInError, rhs: LiveCheckInManager.LiveCheckInError) -> Bool {
        switch (lhs, rhs) {
        case (.alreadyActive, .alreadyActive): return true
        }
    }
}
