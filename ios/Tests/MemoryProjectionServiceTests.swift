import XCTest

@MainActor
final class MemoryProjectionServiceTests: XCTestCase {

    private var service: MemoryProjectionService!
    private var store: MockMemoryProjectionStore!
    private var memoryService: MemoryService!

    override func setUp() {
        super.setUp()
        store = MockMemoryProjectionStore()
        memoryService = MemoryService(storageService: nil, geminiService: nil, userId: "test-user")
        service = MemoryProjectionService(
            sessionStore: store,
            storageService: nil,
            geminiService: nil,
            userId: "test-user"
        )
    }

    override func tearDown() {
        service = nil
        memoryService = nil
        store = nil
        super.tearDown()
    }

    func testDrainPendingMemoryProjections_replaysStoredPayloadAndMarksCompleted() async {
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: "session-1",
                kind: .memoryProjection,
                payloadJSON: MemoryProjectionService.makePayloadJSON(
                    sessionId: "session-1",
                    source: "unified",
                    intent: "casual",
                    transcript: [
                        (role: "user", text: "I'm eating salsa right now."),
                        (role: "assistant", text: "That sounds tasty.")
                    ]
                )
            )
        ]

        await service.drainPendingMemoryProjections(using: memoryService)

        XCTAssertTrue(memoryService.episodicMemories.contains(where: {
            $0.summary.contains("eating salsa")
        }))
        XCTAssertEqual(store.savedOutboxItems.first?.status, .completed)
        XCTAssertEqual(store.savedOutboxItems.first?.attemptCount, 1)
        XCTAssertNotNil(store.savedOutboxItems.first?.receiptId)
        XCTAssertNotNil(store.savedOutboxItems.first?.completedAt)
    }

    func testDrainPendingMemoryProjections_rebuildsTranscriptFromSessionEventsWhenPayloadMissing() async {
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: "session-2",
                kind: .memoryProjection
            )
        ]
        store.sessionEventsBySession["session-2"] = [
            CompanionSessionEvent(
                sessionId: "session-2",
                sequenceNumber: 0,
                type: .sessionStarted,
                source: "live"
            ),
            CompanionSessionEvent(
                sessionId: "session-2",
                sequenceNumber: 1,
                type: .userUtterance,
                source: "live",
                text: "I just generated a song about the rain."
            ),
            CompanionSessionEvent(
                sessionId: "session-2",
                sequenceNumber: 2,
                type: .assistantUtterance,
                source: "live",
                text: "That sounds beautiful."
            )
        ]

        await service.drainPendingMemoryProjections(using: memoryService)

        XCTAssertTrue(memoryService.episodicMemories.contains(where: {
            $0.summary.contains("generated a song about the rain")
        }))
        XCTAssertEqual(store.savedOutboxItems.first?.status, .completed)
    }

    func testDrainPendingMemoryProjections_keepsOutboxPendingWhenLLMExtractionFails() async {
        let gemini = FailingMemoryProjectionGeminiService()
        let retryMemoryService = MemoryService(storageService: nil, geminiService: gemini, userId: "test-user")
        service = MemoryProjectionService(
            sessionStore: store,
            storageService: nil,
            geminiService: gemini,
            userId: "test-user"
        )
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: "session-3",
                kind: .memoryProjection,
                payloadJSON: MemoryProjectionService.makePayloadJSON(
                    sessionId: "session-3",
                    source: "unified",
                    intent: "casual",
                    transcript: [
                        (role: "user", text: "I'm eating salsa right now.")
                    ]
                )
            )
        ]

        await service.drainPendingMemoryProjections(using: retryMemoryService)

        XCTAssertEqual(store.savedOutboxItems.first?.status, .pending)
        XCTAssertEqual(store.savedOutboxItems.first?.attemptCount, 1)
        XCTAssertNotNil(store.savedOutboxItems.first?.lastError)
        XCTAssertTrue(retryMemoryService.episodicMemories.contains(where: {
            $0.summary.contains("eating salsa")
        }))
    }

    func testDrainPendingMemoryProjections_retryDoesNotDuplicateAppliedRecentDetail() async {
        let gemini = FailingMemoryProjectionGeminiService()
        let retryMemoryService = MemoryService(storageService: nil, geminiService: gemini, userId: "test-user")
        service = MemoryProjectionService(
            sessionStore: store,
            storageService: nil,
            geminiService: gemini,
            userId: "test-user"
        )
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: "session-4",
                kind: .memoryProjection,
                payloadJSON: MemoryProjectionService.makePayloadJSON(
                    sessionId: "session-4",
                    source: "unified",
                    intent: "casual",
                    transcript: [
                        (role: "user", text: "I'm eating salsa right now.")
                    ]
                )
            )
        ]

        await service.drainPendingMemoryProjections(using: retryMemoryService)
        await service.drainPendingMemoryProjections(using: retryMemoryService)

        XCTAssertEqual(
            retryMemoryService.episodicMemories.filter { $0.summary.contains("eating salsa") }.count,
            1
        )
        XCTAssertEqual(store.savedOutboxItems.first?.attemptCount, 2)
        XCTAssertEqual(store.savedOutboxItems.first?.status, .pending)
    }

    func testDrainPendingMemoryProjections_materializesCreativeArtifactsIntoMemory() async {
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: "session-5",
                kind: .memoryProjection,
                payloadJSON: MemoryProjectionService.makePayloadJSON(
                    sessionId: "session-5",
                    source: "creative",
                    intent: "creative",
                    transcript: [
                        (role: "assistant", text: "Your music is ready.")
                    ],
                    artifacts: [
                        CompanionMemoryProjectionPayload.Artifact(
                            mediaType: "music",
                            prompt: "a gentle rain song"
                        )
                    ]
                )
            )
        ]

        await service.drainPendingMemoryProjections(using: memoryService)

        XCTAssertTrue(memoryService.episodicMemories.contains(where: {
            $0.summary.contains("gentle rain song")
        }))
        XCTAssertEqual(store.savedOutboxItems.first?.status, .completed)
    }

    func testDrainPendingMemoryProjections_rebuildsCreativeArtifactsFromSessionEvents() async {
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: "session-6",
                kind: .memoryProjection
            )
        ]
        store.sessionEventsBySession["session-6"] = [
            CompanionSessionEvent(
                sessionId: "session-6",
                sequenceNumber: 0,
                type: .sessionStarted,
                source: "creative"
            ),
            CompanionSessionEvent(
                sessionId: "session-6",
                sequenceNumber: 1,
                type: .creativeArtifactGenerated,
                source: "creative",
                text: "a sunset over the mountains",
                metadata: ["mediaType": "image"]
            )
        ]

        await service.drainPendingMemoryProjections(using: memoryService)

        XCTAssertTrue(memoryService.episodicMemories.contains(where: {
            $0.summary.contains("sunset over the mountains")
        }))
        XCTAssertEqual(store.savedOutboxItems.first?.status, .completed)
    }
}

@MainActor
private final class MockMemoryProjectionStore: LiveCheckInSessionStore {
    var sessionEventsBySession: [String: [CompanionSessionEvent]] = [:]
    var savedOutboxItems: [CompanionProjectionOutboxItem] = []

    func loadContext(userId: String) async throws -> LiveCheckInContext {
        LiveCheckInContext(profile: nil, recentCheckIns: [], medications: [], vocabularyMap: nil)
    }

    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn? { nil }

    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript? { nil }

    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent] {
        sessionEventsBySession[sessionId] ?? []
    }

    func loadOutboxItems(
        userId: String,
        kind: CompanionProjectionKind,
        statuses: Set<CompanionProjectionStatus>
    ) async throws -> [CompanionProjectionOutboxItem] {
        savedOutboxItems
            .filter { $0.kind == kind && statuses.contains($0.status) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(checkIn: CheckIn, userId: String) async throws -> String { checkIn.id ?? "check-in" }

    func save(transcript: Transcript, userId: String) async throws -> String { transcript.id ?? transcript.checkInId }

    func save(vocabularyMap: VocabularyMap, userId: String) async throws -> String { "vocabulary" }

    func append(sessionEvent: CompanionSessionEvent, userId: String) async throws -> String { sessionEvent.documentId }

    func save(outboxItem: CompanionProjectionOutboxItem, userId: String) async throws -> String {
        if let index = savedOutboxItems.firstIndex(where: { $0.documentId == outboxItem.documentId }) {
            savedOutboxItems[index] = outboxItem
        } else {
            savedOutboxItems.append(outboxItem)
        }
        return outboxItem.documentId
    }
}

private final class FailingMemoryProjectionGeminiService: GeminiService {
    override func sendStructuredRequest(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) async throws -> [String: Any] {
        throw NSError(domain: "MemoryProjectionServiceTests", code: -1)
    }
}
