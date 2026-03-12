import XCTest

@MainActor
final class UnifiedGuidanceServiceTests: XCTestCase {

    private var service: UnifiedGuidanceService!
    private var mockGemini: MockGuidanceGeminiService!

    override func setUp() {
        super.setUp()
        mockGemini = MockGuidanceGeminiService()
        service = UnifiedGuidanceService(geminiService: mockGemini, memoryService: nil)
    }

    // MARK: - FIX: Check-in won't end when user wants to stop

    func testResolveAction_userWantsToEnd_overridesAsk() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "ask",
            uncoveredTopics: ["sleep", "medication"],
            userWantsToEnd: true
        )
        XCTAssertEqual(action, "close", "User agency should override extraction even with topics remaining")
    }

    func testResolveAction_userWantsToEnd_overridesWithAllTopics() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "ask",
            uncoveredTopics: ["mood", "sleep", "symptoms", "medication"],
            userWantsToEnd: true
        )
        XCTAssertEqual(action, "close", "Even with ALL topics remaining, user agency wins")
    }

    func testResolveAction_userWantsToEnd_casual() {
        let action = service.resolveAction(
            extractionAction: "chat",
            uncoveredTopics: [],
            userWantsToEnd: true
        )
        XCTAssertEqual(action, "close", "User agency works in casual mode too")
    }

    // MARK: - Fast-Path Agency Detection

    func testFastPath_wrapUp() {
        XCTAssertTrue(service.detectFastPathAgencySignal("I'd like to wrap up"))
    }

    func testFastPath_letsStop() {
        XCTAssertTrue(service.detectFastPathAgencySignal("let's stop"))
    }

    func testFastPath_imDone() {
        XCTAssertTrue(service.detectFastPathAgencySignal("I'm done"))
    }

    func testFastPath_thatsAll() {
        XCTAssertTrue(service.detectFastPathAgencySignal("that's all"))
    }

    func testFastPath_letsFinish() {
        XCTAssertTrue(service.detectFastPathAgencySignal("let's finish"))
    }

    func testFastPath_noMoreQuestions() {
        XCTAssertTrue(service.detectFastPathAgencySignal("no more questions please"))
    }

    func testFastPath_thatsEnough() {
        XCTAssertTrue(service.detectFastPathAgencySignal("that's enough"))
    }

    func testFastPath_allDone() {
        XCTAssertTrue(service.detectFastPathAgencySignal("all done"))
    }

    func testFastPath_wereDone() {
        XCTAssertTrue(service.detectFastPathAgencySignal("we're done"))
    }

    func testFastPath_normalSpeech_doesNotTrigger() {
        XCTAssertFalse(service.detectFastPathAgencySignal("I slept pretty well last night"))
        XCTAssertFalse(service.detectFastPathAgencySignal("My medication is helping"))
        XCTAssertFalse(service.detectFastPathAgencySignal("I walked for 30 minutes today"))
    }

    // MARK: - LLM-Based Agency Detection (via extraction)

    func testDetectAgencySignal_fromLLMExtraction() {
        // Simulate what happens when LLM detects "I think we're good" (no keyword match)
        // This verifies the architecture supports indirect signals
        XCTAssertFalse(service.detectFastPathAgencySignal("I think we're good"),
            "Indirect signals should NOT match fast-path — they rely on LLM extraction")
        XCTAssertFalse(service.detectFastPathAgencySignal("nothing else comes to mind"),
            "Indirect signals should NOT match fast-path")
        XCTAssertFalse(service.detectFastPathAgencySignal("I need to go now"),
            "Indirect signals should NOT match fast-path")
    }

    func testAddUserTranscript_fastPathSetsFlag() {
        service.suggestCheckIn()
        service.addUserTranscript("let's wrap up")
        XCTAssertTrue(service.userWantsToEnd, "Fast-path keyword should set userWantsToEnd immediately")
    }

    func testAddUserTranscript_ambiguousDoesNotSetFlag() {
        service.addUserTranscript("I think that covers everything")
        XCTAssertFalse(service.userWantsToEnd,
            "Ambiguous phrases should NOT set flag — LLM extraction handles these")
    }

    // MARK: - FIX: Casual conversation shouldn't force check-in

    func testDetectFastPathIntent_drawImage_isCreative() {
        let intent = service.detectFastPathIntent("Can you draw me a picture of a sunset?")
        XCTAssertEqual(intent, .creative)
    }

    func testDetectFastPathIntent_makeImage_isCreative() {
        let intent = service.detectFastPathIntent("make an image of a cat")
        XCTAssertEqual(intent, .creative)
    }

    func testDetectFastPathIntent_generateMusic_isCreative() {
        let intent = service.detectFastPathIntent("can you compose some music?")
        XCTAssertEqual(intent, .creative)
    }

    func testDetectFastPathIntent_joke_isNil() {
        let intent = service.detectFastPathIntent("Tell me a joke")
        XCTAssertNil(intent, "Ambiguous intent should return nil for LLM to decide")
    }

    func testDetectFastPathIntent_weather_isNil() {
        let intent = service.detectFastPathIntent("what's the weather like?")
        XCTAssertNil(intent, "Ambiguous intent should return nil for LLM to decide")
    }

    func testDetectFastPathIntent_checkIn_isCheckin() {
        let intent = service.detectFastPathIntent("Let's do a check-in")
        XCTAssertEqual(intent, .checkin)
    }

    func testDetectFastPathIntent_wellnessCheck_isCheckin() {
        let intent = service.detectFastPathIntent("I want a wellness check")
        XCTAssertEqual(intent, .checkin)
    }

    // MARK: - Full detectIntent (fast-path + LLM fallback)

    func testDetectIntent_usesLLMFallback() {
        // This tests the full intent detection path.
        // Without extraction, ambiguous input defaults to currentIntent.
        let intent = service.detectIntent(from: [
            (role: "user", text: "Tell me a joke")
        ])
        XCTAssertEqual(intent, .casual, "Without LLM extraction, default intent is casual")
    }

    func testDetectIntent_explicitCheckIn() {
        let intent = service.detectIntent(from: [
            (role: "user", text: "Let's check in")
        ])
        XCTAssertEqual(intent, .checkin)
    }

    func testDetectIntent_explicitCreative() {
        let intent = service.detectIntent(from: [
            (role: "user", text: "draw me a sunset")
        ])
        XCTAssertEqual(intent, .creative)
    }

    // MARK: - Action Resolution — Normal Cases

    func testResolveAction_allTopicsCovered_closes() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "close",
            uncoveredTopics: [],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "close")
    }

    func testResolveAction_topicsCovered_reflectAllowed() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "reflect",
            uncoveredTopics: [],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "reflect")
    }

    func testResolveAction_topicsCovered_affirmAllowed() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "affirm",
            uncoveredTopics: [],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "affirm")
    }

    func testResolveAction_topicsRemain_preventsPrematureClose() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "close",
            uncoveredTopics: ["symptoms"],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "ask", "Should override premature close when topics remain")
    }

    func testResolveAction_topicsRemain_preventsPrematureSummarize() {
        service.suggestCheckIn()
        let action = service.resolveAction(
            extractionAction: "summarize",
            uncoveredTopics: ["medication"],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "ask")
    }

    func testResolveAction_casualMode_defaultsToChat() {
        let action = service.resolveAction(
            extractionAction: "ask",
            uncoveredTopics: [],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "chat", "Casual mode should default to chat")
    }

    func testResolveAction_casualMode_respectsReflect() {
        let action = service.resolveAction(
            extractionAction: "reflect",
            uncoveredTopics: [],
            userWantsToEnd: false
        )
        XCTAssertEqual(action, "reflect")
    }

    // MARK: - Transcript Handling

    func testAddUserTranscript_detectsCreativeIntent() {
        service.addUserTranscript("can you draw me a sunset?")
        XCTAssertEqual(service.currentIntent, .creative)
    }

    func testAddUserTranscript_detectsCheckInIntent() {
        service.addUserTranscript("let's check in")
        XCTAssertEqual(service.currentIntent, .checkin)
    }

    func testEmptyTranscript_ignored() {
        service.addUserTranscript("")
        service.addAssistantTranscript("")
        XCTAssertTrue(service.transcript.isEmpty)
    }

    // MARK: - Guidance Output

    func testHandleGetGuidance_returnsExpectedFields() async {
        service.addUserTranscript("hello")

        let guidance = await service.handleGetGuidance()

        XCTAssertNotNil(guidance["intent"])
        XCTAssertNotNil(guidance["action"])
        XCTAssertNotNil(guidance["instruction"])
        XCTAssertNotNil(guidance["emotion"])
        XCTAssertNotNil(guidance["engagementLevel"])
    }

    func testHandleGetGuidance_greetingStaysInChatMode() async {
        service.addUserTranscript("hello?")

        let guidance = await service.handleGetGuidance()

        XCTAssertEqual(guidance["action"] as? String, "chat")
    }

    func testHandleGetGuidance_greetingOverridesFalseCloseExtraction() async {
        mockGemini.structuredResponseToReturn = [
            "emotion": "calm",
            "engagementLevel": "low",
            "recommendedAction": "close",
            "userWantsToEnd": true,
            "detectedIntent": "casual"
        ]
        service.addUserTranscript("hello?")

        let guidance = await service.handleGetGuidance()

        XCTAssertEqual(guidance["intent"] as? String, "casual")
        XCTAssertEqual(guidance["action"] as? String, "chat")
        XCTAssertFalse(service.userWantsToEnd)
    }

    func testHandleGetGuidance_casualIntent() async {
        service.addUserTranscript("tell me a story")

        let guidance = await service.handleGetGuidance()

        XCTAssertEqual(guidance["action"] as? String, "chat")
    }

    func testHandleGetGuidance_checkinIncludesTopics() async {
        service.suggestCheckIn()

        let guidance = await service.handleGetGuidance()

        XCTAssertNotNil(guidance["topicsRemaining"])
        XCTAssertNotNil(guidance["topicsCovered"])
    }

    func testHandleGetGuidance_fastPathAgency_closesImmediately() async {
        service.suggestCheckIn()
        service.addUserTranscript("let's wrap up")

        let guidance = await service.handleGetGuidance()
        XCTAssertEqual(guidance["action"] as? String, "close",
            "Fast-path agency signal should produce close action")
    }

    func testFinalizePendingTranscriptTurn_persistsCanonicalUnifiedSessionEvents() async {
        let store = MockUnifiedSessionStore()
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        service.upsertUserTranscript("I'm eating salsa")
        service.upsertAssistantTranscript("Earlier you mentioned salsa.")

        await service.finalizePendingTranscriptTurn()
        await service.waitForPendingPersistence()

        XCTAssertEqual(
            store.savedSessionEvents.map(\.type),
            [.sessionStarted, .userUtterance, .assistantUtterance]
        )
        XCTAssertEqual(Set(store.savedSessionEvents.map(\.source)), Set(["unified"]))
    }

    func testFinalizePendingTranscriptTurn_upsertsMemoryProjectionOutboxBeforeCompletion() async {
        let store = MockUnifiedSessionStore()
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        service.upsertUserTranscript("I am eating salsa.")
        service.upsertAssistantTranscript("That sounds tasty.")

        await service.finalizePendingTranscriptTurn()
        await service.waitForPendingPersistence()

        XCTAssertEqual(store.savedOutboxItems.count, 1)
        XCTAssertEqual(store.savedOutboxItems.first?.kind, .memoryProjection)
        XCTAssertEqual(store.savedOutboxItems.first?.status, .pending)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("eating salsa") == true)
    }

    func testRecordCreativeArtifact_persistsCreativeEventAndPayload() async {
        let store = MockUnifiedSessionStore()
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        await service.recordCreativeArtifact(
            mediaType: .music,
            prompt: "a gentle rain song"
        )
        await service.waitForPendingPersistence()

        XCTAssertEqual(
            store.savedSessionEvents.map(\.type),
            [.sessionStarted, .creativeArtifactGenerated]
        )
        XCTAssertEqual(store.savedOutboxItems.count, 1)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("\"mediaType\":\"music\"") == true)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("gentle rain song") == true)
    }

    func testHandleCompleteSession_enqueuesMemoryProjectionOutboxOnce() async {
        let store = MockUnifiedSessionStore()
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        service.upsertUserTranscript("I'm eating salsa")
        service.upsertAssistantTranscript("That sounds tasty.")

        _ = await service.handleCompleteSession()
        _ = await service.handleCompleteSession()
        await service.waitForPendingPersistence()

        XCTAssertEqual(
            store.savedSessionEvents.filter { $0.type == .sessionCompleted }.count,
            1
        )
        XCTAssertEqual(store.savedOutboxItems.count, 1)
        XCTAssertEqual(store.savedOutboxItems.first?.kind, .memoryProjection)
        XCTAssertNotNil(store.savedOutboxItems.first?.payloadJSON)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("salsa") == true)
    }

    func testHandleGetGuidance_recallQuestionReturnsDirectMemoryInstruction() async {
        let memory = MemoryService(storageService: nil, geminiService: nil, userId: "test-user")
        memory.episodicMemories = [
            EpisodicMemory(
                timestamp: Date().addingTimeInterval(-60),
                summary: "They mentioned they were eating salsa and chips.",
                emotion: nil,
                topicsCovered: ["food", "recent_detail"],
                importance: 0.65,
                decayRate: 0.12,
                source: "recent_detail"
            )
        ]
        service = UnifiedGuidanceService(geminiService: mockGemini, memoryService: memory)

        service.addUserTranscript("What was I just eating?")

        let guidance = await service.handleGetGuidance()

        XCTAssertEqual(guidance["action"] as? String, "chat")
        XCTAssertEqual(
            guidance["memoryRecall"] as? String,
            "Earlier you mentioned you were eating salsa and chips."
        )
        XCTAssertTrue(
            (guidance["instruction"] as? String)?.contains("Earlier you mentioned you were eating salsa and chips.") == true
        )
    }

    func testHandleGetGuidance_creativeCanvasActionUsesCreativeRoutingAndSuppressesRecall() async {
        let memory = MemoryService(storageService: nil, geminiService: nil, userId: "test-user")
        memory.episodicMemories = [
            EpisodicMemory(
                timestamp: Date().addingTimeInterval(-60),
                summary: "They said they generated a dusk shoreline video.",
                emotion: nil,
                topicsCovered: ["creation", "recent_detail"],
                importance: 0.75,
                decayRate: 0.1,
                source: "recent_detail"
            )
        ]
        mockGemini.structuredResponseToReturn = [
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "reflect",
            "userWantsToEnd": false,
            "detectedIntent": "casual",
            "creativeCanvasAction": "show",
            "creativeRequestedMediaType": "video"
        ]
        service = UnifiedGuidanceService(geminiService: mockGemini, memoryService: memory)

        service.addUserTranscript("show me that video again")

        let guidance = await service.handleGetGuidance()

        XCTAssertEqual(guidance["intent"] as? String, "creative")
        XCTAssertNil(guidance["memoryRecall"])
        XCTAssertTrue(service.shouldRouteThroughCreativeTools)
        XCTAssertEqual(service.latestCreativeCanvasAction, "show")
        XCTAssertEqual(service.latestCreativeRequestedMediaType, .video)
    }

    // MARK: - CheckIn Persistence

    func testHandleCompleteSession_checkInIntent_persistsCheckInRecord() async {
        let store = MockUnifiedSessionStore()
        mockGemini.structuredResponseToReturn = [
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "ask",
            "userWantsToEnd": false,
            "moodLabel": "positive",
            "moodScore": 4,
            "sleepHours": 7.5,
            "topicsCovered": ["mood", "sleep"],
            "topicsNotYetCovered": ["symptoms", "medication"]
        ]
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        service.suggestCheckIn()
        service.addUserTranscript("I slept well, feeling good today")
        _ = await service.handleGetGuidance()

        _ = await service.handleCompleteSession()
        await service.waitForPendingPersistence()

        XCTAssertEqual(store.savedCheckIns.count, 1)
        let checkIn = store.savedCheckIns[0]
        XCTAssertEqual(checkIn.userId, "test-user")
        XCTAssertEqual(checkIn.pipelineMode, "unified")
        XCTAssertEqual(checkIn.completionStatus, .completed)
        XCTAssertNotNil(checkIn.completedAt)
        XCTAssertEqual(checkIn.mood?.label, "positive")
        XCTAssertEqual(checkIn.mood?.score, 4)
        XCTAssertEqual(checkIn.sleep?.hours, 7.5)
        XCTAssertNotNil(checkIn.aiSummary)
    }

    func testHandleCompleteSession_checkInIntent_exposesCompletedCheckIn() async {
        let store = MockUnifiedSessionStore()
        mockGemini.structuredResponseToReturn = [
            "emotion": "calm",
            "engagementLevel": "medium",
            "recommendedAction": "ask",
            "userWantsToEnd": false,
            "moodLabel": "positive",
            "moodScore": 4
        ]
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        service.suggestCheckIn()
        service.addUserTranscript("feeling great today")
        _ = await service.handleGetGuidance()

        XCTAssertNil(service.completedCheckIn, "Should be nil before completion")
        XCTAssertNotNil(service.latestExtractionResult, "Extraction should be available after guidance")

        _ = await service.handleCompleteSession()
        await service.waitForPendingPersistence()

        XCTAssertNotNil(service.completedCheckIn, "Should be populated after completion")
        XCTAssertEqual(service.completedCheckIn?.userId, "test-user")
        XCTAssertEqual(service.completedCheckIn?.completionStatus, .completed)
    }

    func testHandleCompleteSession_casualIntent_noCheckInPersisted() async {
        let store = MockUnifiedSessionStore()
        service = UnifiedGuidanceService(
            geminiService: mockGemini,
            memoryService: nil,
            sessionStore: store,
            userId: "test-user"
        )

        service.addUserTranscript("Tell me a joke")
        service.addAssistantTranscript("Why did the chicken cross the road?")

        _ = await service.handleCompleteSession()
        await service.waitForPendingPersistence()

        XCTAssertTrue(store.savedCheckIns.isEmpty,
            "Casual sessions should not create CheckIn records")
    }

    // MARK: - Tool Declarations

    func testUnifiedToolDeclarations() {
        let tools = UnifiedGuidanceService.unifiedToolDeclarations
        XCTAssertEqual(tools.count, 2)

        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("get_guidance"))
        XCTAssertTrue(names.contains("complete_session"))
    }

    func testToolDeclarations_haveDescriptions() {
        for tool in UnifiedGuidanceService.unifiedToolDeclarations {
            XCTAssertNotNil(tool["description"])
            XCTAssertNotNil(tool["parameters"])
        }
    }
}

private final class MockGuidanceGeminiService: GeminiService {
    var structuredResponseToReturn: [String: Any] = [:]
    var textResponseToReturn: String = "Summary stub"

    override func sendStructuredRequest(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) async throws -> [String: Any] {
        structuredResponseToReturn
    }

    override func sendTextRequest(text: String) async throws -> String {
        textResponseToReturn
    }
}

@MainActor
private final class MockUnifiedSessionStore: LiveCheckInSessionStore {
    var savedSessionEvents: [CompanionSessionEvent] = []
    var savedOutboxItems: [CompanionProjectionOutboxItem] = []
    var savedCheckIns: [CheckIn] = []

    func loadContext(userId: String) async throws -> LiveCheckInContext {
        LiveCheckInContext(profile: nil, recentCheckIns: [], medications: [], vocabularyMap: nil)
    }

    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn? { nil }

    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript? { nil }

    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent] { [] }

    func save(checkIn: CheckIn, userId: String) async throws -> String {
        savedCheckIns.append(checkIn)
        return checkIn.id ?? "check-in"
    }

    func save(transcript: Transcript, userId: String) async throws -> String { transcript.id ?? transcript.checkInId }

    func save(vocabularyMap: VocabularyMap, userId: String) async throws -> String { "vocabulary" }

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
}
