import Foundation

/// Conversation intent detected from transcript.
enum ConversationIntent: String {
    case checkin
    case casual
    case creative
}

/// Unified guidance service replacing mode-specific guidance. Detects intent naturally,
/// respects user agency signals, and provides guidance via the get_guidance tool call
/// in the Gemini Live session.
///
/// Agency detection is two-layered:
/// 1. **Fast-path keywords** — a small set of unambiguous phrases caught immediately on
///    transcript arrival so we never wait for the next extraction round.
/// 2. **LLM extraction** — the primary detector. The extraction prompt asks Gemini to set
///    `userWantsToEnd = true` whenever the user signals they want to stop, regardless of
///    phrasing. This catches indirect signals like "I think we're good" or "nothing else".
///
/// Intent detection follows the same pattern: fast-path keywords for obvious cases,
/// LLM `detectedIntent` field for everything else.
@MainActor
final class UnifiedGuidanceService {

    // MARK: - Dependencies

    private let geminiService: GeminiService
    private let memoryService: MemoryService?
    private let sessionStore: LiveCheckInSessionStore?
    private let userId: String?

    // MARK: - State

    private(set) var currentIntent: ConversationIntent = .casual
    private(set) var uncoveredTopics: [String] = []
    private(set) var transcript: [(role: String, text: String)] = []
    private(set) var userWantsToEnd = false
    private var lastExtraction: ExtractionResult?
    private var persistedCheckIn: CheckIn?
    private var checkInActive = false
    private var lockedIntent: ConversationIntent?
    private var sessionId: String?
    private var sessionStartedAt: Date?
    private var nextEventSequence = 0
    private var completionTask: Task<[String: Any], Never>?
    private var completionResult: [String: Any]?
    private var pendingPersistenceTask: Task<Void, Never>?
    private var pendingTurnUserEventText: String?
    private var pendingTurnAssistantEventText: String?
    private var creativeArtifacts: [CompanionMemoryProjectionPayload.Artifact] = []

    // MARK: - Tool Declarations

    static let unifiedToolDeclarations: [[String: Any]] = [
        [
            "name": "get_guidance",
            "description": "Get guidance for the current conversation. Call this BEFORE every response to understand the person's intent, what topics to cover, their emotional state, and what action to take. Always call this.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ],
        [
            "name": "complete_session",
            "description": "Complete the current session. Call this when the conversation is naturally ending, when the person says they're done, or when all check-in topics have been covered and the person is ready to wrap up.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ]
    ]

    // MARK: - Init

    init(
        geminiService: GeminiService,
        memoryService: MemoryService?,
        sessionStore: LiveCheckInSessionStore? = nil,
        userId: String? = nil
    ) {
        self.geminiService = geminiService
        self.memoryService = memoryService
        self.sessionStore = sessionStore
        self.userId = userId
    }

    // MARK: - Transcript

    func waitForPendingPersistence() async {
        await pendingPersistenceTask?.value
    }

    func addUserTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        ensureSessionStarted()
        transcript.append((role: "user", text: text))
        pendingTurnUserEventText = nil

        // Fast-path: catch unambiguous agency signals immediately
        if detectFastPathAgencySignal(text) {
            userWantsToEnd = true
        }

        // Fast-path: catch obvious intent signals immediately
        if let fastIntent = detectFastPathIntent(text) {
            currentIntent = fastIntent
            lockedIntent = fastIntent
            if fastIntent == .checkin && !checkInActive {
                checkInActive = true
                uncoveredTopics = ["mood", "sleep", "symptoms", "medication"]
            }
        }

        if let event = makeSessionEvent(type: .userUtterance, text: text) {
            schedulePersistence(sessionEvents: [event])
        }
    }

    func addAssistantTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        ensureSessionStarted()
        transcript.append((role: "assistant", text: text))
        pendingTurnAssistantEventText = nil

        if let event = makeSessionEvent(type: .assistantUtterance, text: text) {
            schedulePersistence(sessionEvents: [event])
        }
    }

    func upsertUserTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        ensureSessionStarted()
        upsertTranscript(role: "user", text: text)

        // Fast-path: catch unambiguous agency signals immediately
        if detectFastPathAgencySignal(text) {
            userWantsToEnd = true
        }

        // Fast-path: catch obvious intent signals immediately
        if let fastIntent = detectFastPathIntent(text) {
            currentIntent = fastIntent
            lockedIntent = fastIntent
            if fastIntent == .checkin && !checkInActive {
                checkInActive = true
                uncoveredTopics = ["mood", "sleep", "symptoms", "medication"]
            }
        }

        pendingTurnUserEventText = text
    }

    func upsertAssistantTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        ensureSessionStarted()
        upsertTranscript(role: "assistant", text: text)
        pendingTurnAssistantEventText = text
    }

    /// Suggest check-in mode (e.g., when user taps the check-in button).
    func suggestCheckIn() {
        currentIntent = .checkin
        lockedIntent = .checkin
        checkInActive = true
        uncoveredTopics = ["mood", "sleep", "symptoms", "medication"]
    }

    // MARK: - Guidance (called by Gemini via function call)

    func handleGetGuidance() async -> [String: Any] {
        // Run extraction when we have transcript, but with a 4-second timeout
        // so we never block the Gemini tool response for too long. If extraction
        // is slow, we return guidance based on whatever state we already have.
        if !transcript.isEmpty {
            let extractionTask = Task { @MainActor [weak self] in
                await self?.runExtraction()
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                extractionTask.cancel()
            }
            await extractionTask.value
            timeoutTask.cancel()
        }

        let shouldForceOpeningChat = shouldTreatOpeningGreetingAsChat()
        if shouldForceOpeningChat {
            currentIntent = .casual
            userWantsToEnd = false
            if var extraction = lastExtraction {
                extraction.userWantsToEnd = false
                extraction.detectedIntent = ConversationIntent.casual.rawValue
                lastExtraction = extraction
            }
        }

        let recallResponse: String?
        if let latestUserText = latestUserTranscript,
           lastExtraction?.creativeCanvasAction == nil {
            recallResponse = memoryService?.recallResponse(for: latestUserText)
        } else {
            recallResponse = nil
        }

        let resolvedIntent = effectiveIntent
        let resolvedAction: String
        if shouldForceOpeningChat {
            resolvedAction = "chat"
        } else if recallResponse != nil {
            resolvedAction = "chat"
        } else if lockedIntent == .casual && !userWantsToEnd && !checkInActive {
            resolvedAction = "chat"
        } else {
            resolvedAction = resolveAction(
                extractionAction: lastExtraction?.recommendedAction ?? "chat",
                uncoveredTopics: uncoveredTopics,
                userWantsToEnd: userWantsToEnd
            )
        }

        let instruction: String
        if shouldForceOpeningChat {
            instruction = "Greet them warmly and invite them to share what's on their mind."
        } else if let recallResponse {
            instruction = "They are asking what you remember from earlier. Answer directly using this memory: \(recallResponse)"
        } else {
            instruction = buildInstruction(action: resolvedAction)
        }

        var guidance: [String: Any] = [
            "intent": shouldForceOpeningChat ? ConversationIntent.casual.rawValue : resolvedIntent.rawValue,
            "action": resolvedAction,
            "instruction": instruction,
            "emotion": lastExtraction?.emotion ?? "calm",
            "engagementLevel": lastExtraction?.engagementLevel ?? "medium"
        ]

        if let recallResponse {
            guidance["memoryRecall"] = recallResponse
        }

        if checkInActive {
            guidance["topicsCovered"] = lastExtraction?.topicsCovered ?? []
            guidance["topicsRemaining"] = uncoveredTopics
        }

        // Clear the end signal after it's been acted on
        if resolvedAction == "close" {
            userWantsToEnd = false
        }

        return guidance
    }

    func finalizePendingTranscriptTurn() async {
        ensureSessionStarted()

        var events: [CompanionSessionEvent] = []
        if let text = pendingTurnUserEventText,
           let event = makeSessionEvent(type: .userUtterance, text: text) {
            events.append(event)
        }
        if let text = pendingTurnAssistantEventText,
           let event = makeSessionEvent(type: .assistantUtterance, text: text) {
            events.append(event)
        }

        pendingTurnUserEventText = nil
        pendingTurnAssistantEventText = nil

        guard !events.isEmpty else { return }
        await persist(sessionEvents: events, outboxItems: makeProjectionOutboxItems())
    }

    func recordCreativeArtifact(
        mediaType: CreativeMediaType,
        prompt: String
    ) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        ensureSessionStarted()

        let artifact = CompanionMemoryProjectionPayload.Artifact(
            mediaType: mediaType.rawValue,
            prompt: trimmedPrompt
        )
        if !creativeArtifacts.contains(where: {
            $0.mediaType == artifact.mediaType && $0.prompt == artifact.prompt
        }) {
            creativeArtifacts.append(artifact)
        }

        await persist(
            sessionEvents: [
                makeSessionEvent(
                    type: .creativeArtifactGenerated,
                    text: trimmedPrompt,
                    metadata: ["mediaType": mediaType.rawValue]
                )
            ].compactMap { $0 },
            outboxItems: makeProjectionOutboxItems()
        )
    }

    func handleCompleteSession() async -> [String: Any] {
        if let completionTask {
            return await completionTask.value
        }
        if let completionResult {
            return completionResult
        }
        guard !transcript.isEmpty else {
            return ["success": true]
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return ["success": false, "error": "Unified guidance released"]
            }

            self.ensureSessionStarted()
            await self.finalizePendingTranscriptTurn()
            await self.persist(
                sessionEvents: [self.makeSessionEvent(type: .sessionCompleted)].compactMap { $0 },
                outboxItems: self.makeProjectionOutboxItems()
            )

            // Create a CheckIn record so journal/history can display this session
            if self.checkInActive || self.currentIntent == .checkin {
                await self.persistCheckIn()
            }

            let result: [String: Any] = ["success": true]
            self.completionResult = result
            return result
        }

        completionTask = task
        let result = await task.value
        completionResult = result
        return result
    }

    // MARK: - Intent Detection (fast-path)

    /// Keyword fast-path for obvious intent signals. Returns nil if ambiguous —
    /// the LLM extraction (`detectedIntent`) handles the rest.
    func detectFastPathIntent(_ text: String) -> ConversationIntent? {
        let lower = text.lowercased()

        // Creative — very specific verbs that almost always mean generation
        let creativeVerbs = ["draw", "paint", "sketch", "illustrate", "compose"]
        let creativePatterns = ["make an image", "make a picture", "make a video",
                                "make music", "generate an image", "generate a picture",
                                "create an image", "create a picture"]
        if creativeVerbs.contains(where: { lower.contains($0) }) ||
           creativePatterns.contains(where: { lower.contains($0) }) {
            return .creative
        }

        // Casual requests that should not be reclassified into creative mode.
        let casualPatterns = ["tell me a story", "read me a story"]
        if casualPatterns.contains(where: { lower.contains($0) }) {
            return .casual
        }

        // Check-in — explicit requests only
        let checkinPatterns = ["check in", "check-in", "checkin",
                               "let's do a check", "wellness check", "health update"]
        if checkinPatterns.contains(where: { lower.contains($0) }) {
            return .checkin
        }

        // If already in check-in mode, stay there
        if checkInActive { return .checkin }

        return nil  // let LLM decide
    }

    /// Public intent detection combining fast-path + LLM state.
    /// Used by handleGetGuidance and tests.
    func detectIntent(from transcript: [(role: String, text: String)]) -> ConversationIntent {
        guard let lastUser = transcript.last(where: { $0.role == "user" }) else {
            return currentIntent
        }

        // Try fast-path first
        if let fast = detectFastPathIntent(lastUser.text) {
            return fast
        }

        // Fall back to LLM detection from last extraction
        if let llmIntent = lastExtraction?.detectedIntent,
           let intent = ConversationIntent(rawValue: llmIntent) {
            return intent
        }

        return currentIntent
    }

    // MARK: - Action Resolution

    /// Resolves the final action. User agency ALWAYS wins over extraction.
    func resolveAction(
        extractionAction: String,
        uncoveredTopics: [String],
        userWantsToEnd: Bool
    ) -> String {
        // User wants to end → close immediately, no matter what
        if userWantsToEnd {
            return "close"
        }

        // If not in check-in mode, follow extraction or default to chat
        guard checkInActive else {
            if currentIntent == .creative { return "create" }
            return extractionAction == "reflect" || extractionAction == "affirm"
                ? extractionAction
                : "chat"
        }

        // Check-in mode: respect topic coverage
        if uncoveredTopics.isEmpty {
            if extractionAction == "reflect" || extractionAction == "affirm" {
                return extractionAction
            }
            return "close"
        }

        // Topics remain — never close prematurely (unless user wants to end, handled above)
        if extractionAction == "close" || extractionAction == "summarize" {
            return "ask"
        }

        return extractionAction
    }

    // MARK: - Agency Detection

    /// Fast-path keyword detection for unambiguous end signals.
    /// These are obvious enough that we don't need to wait for an LLM round-trip.
    /// The LLM extraction (`userWantsToEnd`) catches everything else —
    /// indirect phrases, disengagement, non-English equivalents, etc.
    func detectFastPathAgencySignal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let signals = [
            "wrap up", "let's stop", "i'm done", "we're done", "all done",
            "that's all", "that's enough", "let's finish", "no more questions"
        ]
        return signals.contains(where: { lower.contains($0) })
    }

    /// Legacy API — checks both fast-path and LLM state.
    func detectAgencySignal(_ text: String) -> String? {
        if detectFastPathAgencySignal(text) {
            return text.lowercased()
        }
        if lastExtraction?.userWantsToEnd == true {
            return "llm_detected"
        }
        return nil
    }

    // MARK: - Private

    private func runExtraction() async {
        let conversationText = transcript
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n")

        guard !conversationText.isEmpty else { return }

        do {
            var extractionPrompt = PromptService.extractionSystemPrompt
            extractionPrompt = extractionPrompt.replacingOccurrences(
                of: "{MEDICATION_LIST}",
                with: ""
            )

            let jsonDict = try await geminiService.sendStructuredRequest(
                text: conversationText,
                systemInstruction: extractionPrompt,
                jsonSchema: ExtractionResult.geminiSchema
            )
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
            let result = try JSONDecoder().decode(ExtractionResult.self, from: jsonData)

            lastExtraction = result

            // LLM-based agency detection — the primary detector
            if result.userWantsToEnd == true {
                userWantsToEnd = true
            }

            // LLM-based intent detection — update if provided
            if lockedIntent == nil,
               let llmIntent = result.detectedIntent,
               let intent = ConversationIntent(rawValue: llmIntent) {
                currentIntent = intent
                if intent == .checkin && !checkInActive {
                    checkInActive = true
                    uncoveredTopics = ["mood", "sleep", "symptoms", "medication"]
                }
            }

            // Update topic tracking
            if let notYetCovered = result.topicsNotYetCovered {
                uncoveredTopics = notYetCovered
            } else if let covered = result.topicsCovered, !covered.isEmpty {
                let allTopics = ["mood", "sleep", "symptoms", "medication"]
                uncoveredTopics = allTopics.filter { !covered.contains($0) }
            }
        } catch {
            print("[UnifiedGuidanceService] Extraction failed: \(error)")
        }
    }

    private func buildInstruction(action: String) -> String {
        let nextTopic = uncoveredTopics.first ?? ""

        switch action {
        case "ask":
            if nextTopic.isEmpty {
                return "Ask if there's anything else on their mind."
            }
            return "Naturally transition to asking about \(nextTopic)."
        case "reflect":
            return "They shared something meaningful. Reflect it back warmly."
        case "affirm":
            return "They shared a win or positive effort. Celebrate it genuinely."
        case "close":
            return "Wrap up warmly. Summarize what you discussed. Call complete_session."
        case "create":
            return "Begin creative collaboration. Reflect their idea back, ask one clarifying question."
        case "chat":
            return "Just be present. Answer their question or engage with their topic naturally."
        default:
            return "Respond naturally to what they said."
        }
    }

    private func upsertTranscript(role: String, text: String) {
        if let lastRole = transcript.last?.role, lastRole == role {
            transcript[transcript.count - 1].text = text
        } else {
            transcript.append((role: role, text: text))
        }
    }

    private var latestUserTranscript: String? {
        transcript.last(where: { $0.role == "user" })?.text
    }

    var shouldRouteThroughCreativeTools: Bool {
        effectiveIntent == .creative
    }

    var latestUserTranscriptText: String? {
        latestUserTranscript
    }

    var latestCreativeCanvasAction: String? {
        lastExtraction?.creativeCanvasAction
    }

    var latestCreativeRequestedMediaType: CreativeMediaType? {
        guard let rawValue = lastExtraction?.creativeRequestedMediaType else { return nil }
        return CreativeMediaType(rawValue: rawValue)
    }

    /// The CheckIn persisted by `handleCompleteSession()`, if any.
    var completedCheckIn: CheckIn? { persistedCheckIn }

    /// The latest extraction result from the conversation.
    var latestExtractionResult: ExtractionResult? { lastExtraction }

    private var effectiveIntent: ConversationIntent {
        if lastExtraction?.creativeCanvasAction != nil {
            return .creative
        }
        return currentIntent
    }

    private func ensureSessionStarted() {
        guard sessionId == nil else { return }
        sessionId = UUID().uuidString
        sessionStartedAt = Date()
        nextEventSequence = 0

        if let startEvent = makeSessionEvent(
            type: .sessionStarted,
            metadata: ["intent": currentIntent.rawValue]
        ) {
            schedulePersistence(sessionEvents: [startEvent])
        }
    }

    private func schedulePersistence(
        sessionEvents: [CompanionSessionEvent] = [],
        outboxItems: [CompanionProjectionOutboxItem] = []
    ) {
        let previousTask = pendingPersistenceTask
        pendingPersistenceTask = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.persist(sessionEvents: sessionEvents, outboxItems: outboxItems)
        }
    }

    private func persist(
        sessionEvents: [CompanionSessionEvent] = [],
        outboxItems: [CompanionProjectionOutboxItem] = []
    ) async {
        guard let sessionStore, let userId else { return }

        do {
            for event in sessionEvents {
                _ = try await sessionStore.append(sessionEvent: event, userId: userId)
            }
            for outboxItem in outboxItems {
                _ = try await sessionStore.save(outboxItem: outboxItem, userId: userId)
            }
        } catch {
            print("[UnifiedGuidanceService] Event persistence error: \(error)")
        }
    }

    private func persistCheckIn() async {
        guard let sessionStore, let userId, let sessionId else { return }

        var checkIn = CheckIn(userId: userId, type: .adhoc, pipelineMode: "unified")
        checkIn.id = sessionId
        if let sessionStartedAt {
            checkIn.startedAt = sessionStartedAt
        }

        if let extraction = lastExtraction {
            extraction.applyToCheckIn(&checkIn)
        }

        checkIn.completionStatus = .completed
        checkIn.completedAt = Date()
        checkIn.durationSeconds = Int(Date().timeIntervalSince(checkIn.startedAt))

        // Generate a brief AI summary from transcript
        let conversationText = transcript
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n")
        if !conversationText.isEmpty {
            let prompt = "Summarize this wellness check-in in under 20 words. State only facts mentioned: mood, sleep hours, symptoms, medications. No filler.\n\nConversation:\n\(conversationText)"
            if let summary = try? await geminiService.sendTextRequest(text: prompt) {
                checkIn.aiSummary = summary
            }
        }

        do {
            _ = try await sessionStore.save(checkIn: checkIn, userId: userId)
            persistedCheckIn = checkIn
            print("[UnifiedGuidanceService] CheckIn persisted (id=\(sessionId))")
        } catch {
            print("[UnifiedGuidanceService] CheckIn persistence error: \(error)")
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
            source: "unified",
            text: text,
            metadata: metadata,
            evidenceRef: sessionId
        )
        nextEventSequence += 1
        return event
    }

    private func makeProjectionOutboxItems() -> [CompanionProjectionOutboxItem] {
        guard let sessionId else { return [] }

        return [
            CompanionProjectionOutboxItem(
                sessionId: sessionId,
                kind: .memoryProjection,
                evidenceRef: sessionId,
                payloadJSON: MemoryProjectionService.makePayloadJSON(
                    sessionId: sessionId,
                    source: "unified",
                    intent: currentIntent.rawValue,
                    transcript: transcript,
                    artifacts: creativeArtifacts
                )
            )
        ]
    }

    private func shouldTreatOpeningGreetingAsChat() -> Bool {
        guard !checkInActive, transcript.count == 1 else { return false }
        guard let latestUserText = transcript.last?.text else { return false }
        return isGreetingOnly(latestUserText)
    }

    private func isGreetingOnly(_ text: String) -> Bool {
        let greetings = [
            "good afternoon",
            "good evening",
            "good morning",
            "hello",
            "hello there",
            "hey",
            "hey there",
            "hi",
            "hi there"
        ]
        return greetings.contains(normalizedUtterance(text))
    }

    private func normalizedUtterance(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
