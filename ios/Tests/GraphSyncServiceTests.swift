import XCTest

@MainActor
final class GraphSyncServiceTests: XCTestCase {

    // MARK: - Stub URL Protocol (captures requests instead of hitting network)

    private class StubURLProtocol: URLProtocol {
        static var lastRequest: URLRequest?
        static var lastBody: Data?
        static var stubbedError: Error?
        static var responseBody: Data = Data("{\"status\":\"ok\",\"eventId\":\"evt\",\"duplicate\":false}".utf8)

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            Self.lastBody = request.httpBody ?? readInputStream(request.httpBodyStream)

            if let error = Self.stubbedError {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Self.responseBody)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset() {
            lastRequest = nil
            lastBody = nil
            stubbedError = nil
            responseBody = Data("{\"status\":\"ok\",\"eventId\":\"evt\",\"duplicate\":false}".utf8)
        }

        private func readInputStream(_ stream: InputStream?) -> Data? {
            guard let stream = stream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 1024)
                if read > 0 { data.append(buffer, count: read) }
            }
            return data
        }
    }

    private var session: URLSession!
    private var service: GraphSyncService!
    private var store: MockGraphSyncStore!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        store = MockGraphSyncStore()

        let client = BackendClient(
            baseURL: URL(string: "https://test.example.com")!,
            session: session
        )
        service = GraphSyncService(client: client, sessionStore: store, userId: "test-user")
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session = nil
        service = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Sync Calls Backend

    func testSyncCheckInCallsBackendPost() async {
        let checkIn = makeCheckIn()
        let extraction = ExtractionResult()

        await service.syncCheckIn(checkIn, extraction: extraction)

        XCTAssertNotNil(StubURLProtocol.lastRequest)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")

        let url = StubURLProtocol.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("/api/graph/ingest"), "Expected path /api/graph/ingest, got: \(url)")
    }

    func testSyncCheckInPersistsGraphOutboxPayloadAndMarksCompleted() async {
        let checkIn = makeCheckIn()
        let extraction = ExtractionResult()

        await service.syncCheckIn(checkIn, extraction: extraction)

        XCTAssertEqual(store.savedOutboxItems.count, 1)
        let item = try? XCTUnwrap(store.savedOutboxItems.first)
        XCTAssertEqual(item?.kind, .graphSync)
        XCTAssertEqual(item?.status, .completed)
        XCTAssertNotNil(item?.payloadJSON)
    }

    func testDrainPendingGraphSyncsRetriesStoredPayload() async throws {
        let checkIn = makeCheckIn()
        let extraction = ExtractionResult()
        let payload = GraphSyncService.makePayload(
            checkIn: checkIn,
            extraction: extraction,
            eventId: "\(checkIn.id ?? "unknown")_graph_sync"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadJSON = String(decoding: try encoder.encode(payload), as: UTF8.self)
        store.savedOutboxItems = [
            CompanionProjectionOutboxItem(
                sessionId: checkIn.id ?? "unknown",
                kind: .graphSync,
                payloadJSON: payloadJSON
            )
        ]

        await service.drainPendingGraphSyncs()

        XCTAssertNotNil(StubURLProtocol.lastRequest)
        XCTAssertEqual(store.savedOutboxItems.first?.status, .completed)
    }

    // MARK: - Sync Failure Does Not Throw

    func testSyncFailureDoesNotThrow() async {
        StubURLProtocol.stubbedError = NSError(domain: "test", code: -1)

        let checkIn = makeCheckIn()
        let extraction = ExtractionResult()

        // Should not throw — fire-and-forget behavior
        await service.syncCheckIn(checkIn, extraction: extraction)
    }

    func testSyncFailureUpdatesOutboxAttemptState() async {
        StubURLProtocol.stubbedError = NSError(domain: "test", code: -1)

        let checkIn = makeCheckIn()
        let extraction = ExtractionResult()

        await service.syncCheckIn(checkIn, extraction: extraction)

        XCTAssertEqual(store.savedOutboxItems.first?.status, .pending)
        XCTAssertEqual(store.savedOutboxItems.first?.attemptCount, 1)
        XCTAssertNotNil(store.savedOutboxItems.first?.lastError)
    }

    // MARK: - Payload Includes Triggers, Activities, Concerns

    func testPayloadIncludesTriggersActivitiesConcerns() async throws {
        let checkIn = makeCheckIn()
        let extraction = ExtractionResult(
            triggers: [
                ExtractedTrigger(name: "loud noise", type: "environmental", userWords: "the dog was barking")
            ],
            activities: [
                ExtractedActivity(name: "physical therapy", duration: "45 minutes", intensity: "moderate")
            ],
            concerns: [
                ExtractedConcern(text: "worried about balance", theme: "mobility", urgency: "medium")
            ]
        )

        await service.syncCheckIn(checkIn, extraction: extraction)

        let body = StubURLProtocol.lastBody
        XCTAssertNotNil(body)

        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        XCTAssertNotNil(json)

        let checkInPayload = json?["checkIn"] as? [String: Any]
        XCTAssertNotNil(checkInPayload)

        // Triggers
        let triggers = checkInPayload?["triggers"] as? [[String: Any]]
        XCTAssertEqual(triggers?.count, 1)
        XCTAssertEqual(triggers?.first?["name"] as? String, "loud noise")
        XCTAssertEqual(triggers?.first?["type"] as? String, "environmental")

        // Activities
        let activities = checkInPayload?["activities"] as? [[String: Any]]
        XCTAssertEqual(activities?.count, 1)
        XCTAssertEqual(activities?.first?["name"] as? String, "physical therapy")
        XCTAssertEqual(activities?.first?["duration"] as? String, "45 minutes")
        XCTAssertEqual(activities?.first?["intensity"] as? String, "moderate")

        // Concerns
        let concerns = checkInPayload?["concerns"] as? [[String: Any]]
        XCTAssertEqual(concerns?.count, 1)
        XCTAssertEqual(concerns?.first?["text"] as? String, "worried about balance")
        XCTAssertEqual(concerns?.first?["theme"] as? String, "mobility")
        XCTAssertEqual(concerns?.first?["urgency"] as? String, "medium")
    }

    // MARK: - Helpers

    private func makeCheckIn() -> CheckIn {
        var checkIn = CheckIn(userId: "test-user", type: .morning)
        checkIn.completionStatus = .completed
        checkIn.completedAt = Date()
        return checkIn
    }
}

@MainActor
private final class MockGraphSyncStore: LiveCheckInSessionStore {
    var savedOutboxItems: [CompanionProjectionOutboxItem] = []

    func loadContext(userId: String) async throws -> LiveCheckInContext {
        LiveCheckInContext(profile: nil, recentCheckIns: [], medications: [], vocabularyMap: nil)
    }

    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn? { nil }

    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript? { nil }

    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent] { [] }

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
