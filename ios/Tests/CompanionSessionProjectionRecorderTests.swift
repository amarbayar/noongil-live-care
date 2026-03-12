import XCTest

@MainActor
final class CompanionSessionProjectionRecorderTests: XCTestCase {

    func testRecordTurns_startsSessionAndUpsertsPendingMemoryProjection() async {
        let store = MockCompanionSessionProjectionStore()
        let recorder = CompanionSessionProjectionRecorder(
            sessionStore: store,
            userId: "test-user"
        )

        await recorder.recordUserUtterance(
            "I slept okay last night.",
            source: "local",
            intent: "casual"
        )
        await recorder.recordAssistantUtterance(
            "Glad to hear it.",
            source: "local",
            intent: "casual"
        )

        XCTAssertEqual(
            store.savedSessionEvents.map(\.type),
            [.sessionStarted, .userUtterance, .assistantUtterance]
        )
        XCTAssertEqual(store.savedOutboxItems.count, 1)
        XCTAssertEqual(store.savedOutboxItems.first?.status, .pending)
        XCTAssertNil(store.savedOutboxItems.first?.receiptId)
        XCTAssertNil(store.savedOutboxItems.first?.completedAt)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("I slept okay last night") == true)
    }

    func testRecordCreativeArtifact_persistsArtifactEventAndPayload() async {
        let store = MockCompanionSessionProjectionStore()
        let recorder = CompanionSessionProjectionRecorder(
            sessionStore: store,
            userId: "test-user"
        )

        await recorder.recordCreativeArtifact(
            mediaType: .music,
            prompt: "a gentle rain song",
            source: "creative",
            intent: "creative"
        )

        XCTAssertEqual(
            store.savedSessionEvents.map(\.type),
            [.sessionStarted, .creativeArtifactGenerated]
        )
        XCTAssertEqual(store.savedOutboxItems.count, 1)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("gentle rain song") == true)
        XCTAssertTrue(store.savedOutboxItems.first?.payloadJSON?.contains("\"mediaType\":\"music\"") == true)
    }

    func testCompleteSession_isIdempotent() async {
        let store = MockCompanionSessionProjectionStore()
        let recorder = CompanionSessionProjectionRecorder(
            sessionStore: store,
            userId: "test-user"
        )

        await recorder.recordUserUtterance(
            "I am eating salsa.",
            source: "local",
            intent: "casual"
        )
        await recorder.completeSession()
        await recorder.completeSession()

        XCTAssertEqual(
            store.savedSessionEvents.filter { $0.type == .sessionCompleted }.count,
            1
        )
    }
}

@MainActor
private final class MockCompanionSessionProjectionStore: LiveCheckInSessionStore {
    var savedSessionEvents: [CompanionSessionEvent] = []
    var savedOutboxItems: [CompanionProjectionOutboxItem] = []

    func loadContext(userId: String) async throws -> LiveCheckInContext {
        LiveCheckInContext(profile: nil, recentCheckIns: [], medications: [], vocabularyMap: nil)
    }

    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn? { nil }

    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript? { nil }

    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent] {
        savedSessionEvents
            .filter { $0.sessionId == sessionId }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    func loadOutboxItems(
        userId: String,
        kind: CompanionProjectionKind,
        statuses: Set<CompanionProjectionStatus>
    ) async throws -> [CompanionProjectionOutboxItem] {
        savedOutboxItems.filter { $0.kind == kind && statuses.contains($0.status) }
    }

    func save(checkIn: CheckIn, userId: String) async throws -> String { checkIn.id ?? "check-in" }

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
