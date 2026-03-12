import Foundation

@MainActor
final class CompanionSessionProjectionRecorder {
    private let sessionStore: LiveCheckInSessionStore?
    private let userId: String?

    private(set) var sessionId: String?
    private(set) var transcript: [(role: String, text: String)] = []
    private(set) var artifacts: [CompanionMemoryProjectionPayload.Artifact] = []

    private var source: String = "local"
    private var intent: String?
    private var nextEventSequence = 0
    private var isCompleted = false

    init(sessionStore: LiveCheckInSessionStore?, userId: String?) {
        self.sessionStore = sessionStore
        self.userId = userId
    }

    func recordUserUtterance(_ text: String, source: String, intent: String?) async {
        await recordTurn(role: "user", type: .userUtterance, text: text, source: source, intent: intent)
    }

    func recordAssistantUtterance(_ text: String, source: String, intent: String?) async {
        await recordTurn(role: "assistant", type: .assistantUtterance, text: text, source: source, intent: intent)
    }

    func recordCreativeArtifact(
        mediaType: CreativeMediaType,
        prompt: String,
        source: String,
        intent: String?
    ) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        var events = ensureSessionStarted(source: source, intent: intent)
        self.source = source
        self.intent = intent ?? self.intent

        let artifact = CompanionMemoryProjectionPayload.Artifact(
            mediaType: mediaType.rawValue,
            prompt: trimmedPrompt
        )
        if !artifacts.contains(where: { $0.mediaType == artifact.mediaType && $0.prompt == artifact.prompt }) {
            artifacts.append(artifact)
        }

        if let event = makeSessionEvent(
            type: .creativeArtifactGenerated,
            text: trimmedPrompt,
            metadata: ["mediaType": mediaType.rawValue]
        ) {
            events.append(event)
        }

        await persist(sessionEvents: events, upsertOutbox: true)
    }

    func completeSession() async {
        guard sessionId != nil, !isCompleted else { return }
        isCompleted = true

        let events = [makeSessionEvent(type: .sessionCompleted)].compactMap { $0 }
        await persist(sessionEvents: events, upsertOutbox: true)
    }

    func reset() {
        sessionId = nil
        transcript = []
        artifacts = []
        source = "local"
        intent = nil
        nextEventSequence = 0
        isCompleted = false
    }

    private func recordTurn(
        role: String,
        type: CompanionSessionEventType,
        text: String,
        source: String,
        intent: String?
    ) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        var events = ensureSessionStarted(source: source, intent: intent)
        self.source = source
        self.intent = intent ?? self.intent
        transcript.append((role: role, text: trimmedText))

        if let event = makeSessionEvent(type: type, text: trimmedText) {
            events.append(event)
        }

        await persist(sessionEvents: events, upsertOutbox: true)
    }

    private func ensureSessionStarted(source: String, intent: String?) -> [CompanionSessionEvent] {
        guard sessionId == nil else { return [] }

        sessionId = UUID().uuidString
        nextEventSequence = 0
        isCompleted = false
        self.source = source
        self.intent = intent

        guard let startEvent = makeSessionEvent(
            type: .sessionStarted,
            metadata: ["intent": intent ?? "casual"]
        ) else {
            return []
        }
        return [startEvent]
    }

    private func persist(
        sessionEvents: [CompanionSessionEvent],
        upsertOutbox: Bool
    ) async {
        guard let sessionStore, let userId else { return }

        do {
            for event in sessionEvents {
                _ = try await sessionStore.append(sessionEvent: event, userId: userId)
            }

            if upsertOutbox, let outboxItem = makeProjectionOutboxItem() {
                _ = try await sessionStore.save(outboxItem: outboxItem, userId: userId)
            }
        } catch {
            print("[CompanionSessionProjectionRecorder] Persistence error: \(error)")
        }
    }

    private func makeSessionEvent(
        type: CompanionSessionEventType,
        text: String? = nil,
        metadata: [String: String]? = nil
    ) -> CompanionSessionEvent? {
        guard let sessionId else { return nil }

        let event = CompanionSessionEvent(
            sessionId: sessionId,
            sequenceNumber: nextEventSequence,
            type: type,
            source: source,
            text: text,
            metadata: metadata,
            evidenceRef: sessionId
        )
        nextEventSequence += 1
        return event
    }

    private func makeProjectionOutboxItem() -> CompanionProjectionOutboxItem? {
        guard let sessionId else { return nil }

        return CompanionProjectionOutboxItem(
            sessionId: sessionId,
            kind: .memoryProjection,
            status: .pending,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: nil,
            evidenceRef: sessionId,
            payloadJSON: MemoryProjectionService.makePayloadJSON(
                sessionId: sessionId,
                source: source,
                intent: intent,
                transcript: transcript,
                artifacts: artifacts
            ),
            receiptId: nil,
            completedAt: nil
        )
    }
}
