import Foundation

/// Manages check-in state during Gemini Live sessions. Provides guidance context
/// via function calls so Gemini can steer the conversation through health topics
/// without intercepting the audio stream.
@MainActor
final class LiveCheckInManager {

    // MARK: - Dependencies

    private let geminiService: GeminiService
    private let graphSyncService: GraphSyncService?
    private let sessionStore: LiveCheckInSessionStore?
    private let userId: String
    private let companionName: String

    // MARK: - State

    private(set) var isActive = false
    private var transcript: [(role: String, text: String)] = []
    private var transcriptDocument: Transcript?
    private var medications: [Medication] = []
    private var profile: UserProfile?
    private var recentCheckIns: [CheckIn] = []
    private var vocabularyMap = VocabularyMap()
    private var currentCheckIn: CheckIn?
    private var lastExtraction: ExtractionResult?
    private var uncoveredTopics: [String] = ["mood", "sleep", "symptoms", "medication"]
    private var completionTask: Task<[String: Any], Never>?
    private var completionResult: [String: Any]?
    private var pendingAutosaveTask: Task<Void, Never>?
    private var nextEventSequence = 0
    private var pendingTurnUserEventText: String?
    private var pendingTurnAssistantEventText: String?

    /// Called when the check-in completes or is cancelled.
    var onComplete: (() -> Void)?

    var activeCheckInId: String? { currentCheckIn?.id }
    var transcriptEntryCount: Int { transcriptDocument?.entryCount ?? transcript.count }

    func waitForPendingPersistence() async {
        await pendingAutosaveTask?.value
    }

    // MARK: - Tool Declarations

    static let checkInToolDeclarations: [[String: Any]] = [
        [
            "name": "get_check_in_guidance",
            "description": "Get guidance for the current health check-in conversation. Call this BEFORE responding to the member to get context about which topics have been covered, what to ask next, their emotional state, and their active medications. Always call this during a check-in.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ],
        [
            "name": "complete_check_in",
            "description": "Complete the health check-in. Call this when all topics have been naturally covered and it's time to wrap up. This saves the check-in data and syncs it to the health knowledge graph.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ]
    ]

    // MARK: - Init

    init(
        geminiService: GeminiService,
        storageService: StorageService? = nil,
        graphSyncService: GraphSyncService? = nil,
        sessionStore: LiveCheckInSessionStore? = nil,
        userId: String,
        companionName: String = "Mira"
    ) {
        self.geminiService = geminiService
        self.graphSyncService = graphSyncService
        self.sessionStore = sessionStore ?? storageService.map { FirestoreLiveCheckInSessionStore(storageService: $0) }
        self.userId = userId
        self.companionName = companionName
    }

    // MARK: - Start

    /// Loads context, creates a CheckIn record, and returns the system prompt for Gemini Live.
    func start(type: CheckInType = .adhoc) async throws -> String {
        guard !isActive else { throw LiveCheckInError.alreadyActive }

        completionTask = nil
        completionResult = nil
        nextEventSequence = 0
        pendingTurnUserEventText = nil
        pendingTurnAssistantEventText = nil
        await loadContext()

        let didResume = await restoreActiveSession(type: type)
        if !didResume {
            var checkIn = CheckIn(userId: userId, type: type, pipelineMode: "live")
            checkIn.id = UUID().uuidString
            checkIn.checkInNumber = (recentCheckIns.first?.checkInNumber ?? 0) + 1
            currentCheckIn = checkIn
            transcript = []
            transcriptDocument = makeTranscript(for: checkIn)
            await persist(
                sessionEvents: [
                    makeSessionEvent(
                        type: .sessionStarted,
                        metadata: ["checkInType": type.rawValue]
                    )
                ].compactMap { $0 }
            )
            sessionStore?.markStartMode(.new)
        }

        isActive = true
        uncoveredTopics = ["mood", "sleep", "symptoms", "medication"]
        lastExtraction = nil

        // Build system prompt with context
        let basePrompt = PromptService.liveCheckInSystemPrompt
        let context = CompanionContext.build(
            profile: profile,
            recentCheckIns: recentCheckIns,
            medications: medications,
            vocabulary: vocabularyMap,
            companionName: companionName
        )

        let greetingContext = CompanionContext.buildGreetingContext(
            recentCheckIns: recentCheckIns,
            userName: profile?.displayName,
            checkInType: type
        )

        let prompt = basePrompt
            .replacingOccurrences(of: "{CONTEXT}", with: context)
            + "\n\n[Greeting context: \(greetingContext)]"

        print("[LiveCheckInManager] Started Live check-in (type=\(type.rawValue), resumed=\(didResume))")
        return prompt
    }

    // MARK: - Transcript

    func addUserTranscript(_ text: String) {
        guard isActive, !text.isEmpty else { return }
        transcript.append((role: "user", text: text))
        appendTranscriptEntry(role: .user, text: text)
        pendingTurnUserEventText = nil
        if let event = makeSessionEvent(type: .userUtterance, text: text) {
            schedulePersistence(sessionEvents: [event])
        }
    }

    func addAssistantTranscript(_ text: String) {
        guard isActive, !text.isEmpty else { return }
        transcript.append((role: "assistant", text: text))
        appendTranscriptEntry(role: .assistant, text: text)
        pendingTurnAssistantEventText = nil
        if let event = makeSessionEvent(type: .assistantUtterance, text: text) {
            schedulePersistence(sessionEvents: [event])
        }
    }

    func upsertUserTranscript(_ text: String) {
        guard isActive, !text.isEmpty else { return }
        upsertTranscript(role: .user, text: text)
    }

    func upsertAssistantTranscript(_ text: String) {
        guard isActive, !text.isEmpty else { return }
        upsertTranscript(role: .assistant, text: text)
    }

    // MARK: - Guidance (called by Gemini via function call)

    /// Runs extraction on accumulated transcript and returns guidance for the next response.
    func handleGetGuidance() async -> [String: Any] {
        guard isActive else {
            return ["error": "No active check-in"]
        }

        let conversationText = transcript
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n")

        print("[LiveCheckInManager] Transcript for extraction (\(transcript.count) entries):\n\(conversationText.prefix(500))")

        // Run extraction via Gemini REST
        let extraction = await runExtraction(conversationText: conversationText)

        // Build active medication strings
        let activeMeds = medications.filter { $0.isActive }.map { med -> String in
            var desc = med.name
            if let dosage = med.dosage { desc += " \(dosage)" }
            if !med.schedule.isEmpty { desc += " \(med.schedule.joined(separator: "/"))" }
            return desc
        }

        let emotion = extraction?.emotion ?? "calm"
        let engagement = extraction?.engagementLevel ?? "medium"
        let extractionAction = extraction?.recommendedAction ?? "ask"
        let shouldForceOpeningAsk = shouldTreatOpeningGreetingAsOpening()

        // Resolve action — user agency ALWAYS wins, then topic tracking
        let resolvedAction: String
        if shouldForceOpeningAsk {
            resolvedAction = "ask"
        } else if extraction?.userWantsToEnd == true {
            // User wants to end — respect immediately, regardless of uncovered topics
            resolvedAction = "close"
            print("[LiveCheckInManager] User wants to end — closing (LLM detected)")
        } else if uncoveredTopics.isEmpty {
            // All topics genuinely covered — close unless reflecting/affirming
            if extractionAction == "reflect" || extractionAction == "affirm" {
                resolvedAction = extractionAction
            } else {
                resolvedAction = "close"
            }
        } else {
            // Topics remain — never close prematurely (user hasn't asked to end)
            if extractionAction == "close" || extractionAction == "summarize" {
                resolvedAction = "ask"
                print("[LiveCheckInManager] Overriding extraction action '\(extractionAction)' → 'ask' (\(uncoveredTopics.count) topics remain)")
            } else {
                resolvedAction = extractionAction
            }
        }

        let nextTopic = uncoveredTopics.first ?? ""

        // Build instruction hint
        let instruction: String
        switch resolvedAction {
        case "reflect":
            instruction = "They shared something meaningful. Reflect it back warmly, then gently ask about \(nextTopic.isEmpty ? "how else they're doing" : nextTopic)."
        case "affirm":
            instruction = "They shared a win or positive effort. Celebrate it genuinely, then ask about \(nextTopic.isEmpty ? "anything else" : nextTopic)."
        case "close":
            instruction = "All topics are covered. Wrap up warmly and call complete_check_in."
        case "summarize":
            instruction = "Weave together what they've shared so far. Keep it warm and conversational."
        default:
            if shouldForceOpeningAsk {
                instruction = "Greet them warmly, then begin by asking about \(nextTopic.isEmpty ? "how they're feeling" : nextTopic)."
            } else if nextTopic.isEmpty {
                instruction = "Ask if there's anything else on their mind."
            } else {
                instruction = "Naturally transition to asking about \(nextTopic)."
            }
        }

        let guidance: [String: Any] = [
            "topicsCovered": extraction?.topicsCovered ?? [],
            "topicsRemaining": uncoveredTopics,
            "activeMedications": activeMeds,
            "emotion": emotion,
            "engagementLevel": engagement,
            "recommendedAction": resolvedAction,
            "nextTopicHint": nextTopic,
            "instruction": instruction
        ]

        print("[LiveCheckInManager] Guidance: extraction=\(extractionAction) → resolved=\(resolvedAction), covered=\(extraction?.topicsCovered ?? []), remaining=\(uncoveredTopics)")
        return guidance
    }

    // MARK: - Complete (called by Gemini via function call)

    /// Finalizes the check-in, saves to Firestore, and triggers graph sync.
    func handleComplete() async -> [String: Any] {
        if let completionTask {
            return await completionTask.value
        }
        if let completionResult {
            return completionResult
        }
        guard isActive else {
            return ["success": false, "error": "No active check-in"]
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return ["success": false, "error": "Check-in manager released"]
            }

            await self.finalizePendingTranscriptTurn()

            // Finalize check-in
            self.currentCheckIn?.completionStatus = .completed
            self.currentCheckIn?.completedAt = Date()
            if let startedAt = self.currentCheckIn?.startedAt {
                self.currentCheckIn?.durationSeconds = Int(Date().timeIntervalSince(startedAt))
            }

            await self.autosave()

            // Generate AI summary — non-blocking, failure must not block completion
            do {
                let conversationText = self.transcript
                    .map { "\($0.role): \($0.text)" }
                    .joined(separator: "\n")
                if !conversationText.isEmpty {
                    let prompt = "Summarize this wellness check-in in under 20 words. State only facts mentioned: mood, sleep hours, symptoms, medications. No filler.\n\nConversation:\n\(conversationText)"
                    let summary = try await self.geminiService.sendTextRequest(text: prompt)
                    self.currentCheckIn?.aiSummary = summary
                    await self.autosave()
                }
            } catch {
                print("[LiveCheckInManager] AI summary generation failed (non-blocking): \(error)")
            }

            await self.saveVocabulary()
            await self.persist(
                sessionEvents: [self.makeSessionEvent(type: .sessionCompleted)].compactMap { $0 },
                outboxItems: self.makeProjectionOutboxItems(),
                includeAutosave: false
            )

            // Fire-and-forget graph sync
            if let checkIn = self.currentCheckIn, let extraction = self.lastExtraction {
                Task {
                    await self.graphSyncService?.syncCheckIn(checkIn, extraction: extraction)
                }
            }

            let duration = self.currentCheckIn?.durationSeconds ?? 0
            print("[LiveCheckInManager] Completed check-in (duration=\(duration)s)")

            self.isActive = false
            let result: [String: Any] = ["success": true, "durationSeconds": duration]
            self.completionResult = result
            self.onComplete?()
            return result
        }

        completionTask = task
        let result = await task.value
        completionResult = result
        return result
    }

    // MARK: - Cancel

    /// Marks the check-in as abandoned and cleans up.
    func cancel() {
        guard completionTask == nil, completionResult == nil else { return }
        guard isActive else { return }

        currentCheckIn?.completionStatus = .abandoned
        currentCheckIn?.completedAt = Date()
        if let startedAt = currentCheckIn?.startedAt {
            currentCheckIn?.durationSeconds = Int(Date().timeIntervalSince(startedAt))
        }

        let abandonedEvent = makeSessionEvent(type: .sessionAbandoned)
        schedulePersistence(sessionEvents: [abandonedEvent].compactMap { $0 })

        isActive = false
        print("[LiveCheckInManager] Check-in cancelled")
    }

    func finalizePendingTranscriptTurn() async {
        var events: [CompanionSessionEvent] = []
        if let text = pendingTurnUserEventText, let event = makeSessionEvent(type: .userUtterance, text: text) {
            events.append(event)
        }
        if let text = pendingTurnAssistantEventText, let event = makeSessionEvent(type: .assistantUtterance, text: text) {
            events.append(event)
        }

        pendingTurnUserEventText = nil
        pendingTurnAssistantEventText = nil

        guard !events.isEmpty else { return }
        await persist(sessionEvents: events)
    }

    // MARK: - Private — Extraction

    private func runExtraction(conversationText: String) async -> ExtractionResult? {
        guard !conversationText.isEmpty else { return nil }

        var extractionPrompt = PromptService.extractionSystemPrompt
        let medList = medications.filter { $0.isActive }.map { $0.name }.joined(separator: ", ")
        if !medList.isEmpty {
            extractionPrompt = extractionPrompt.replacingOccurrences(
                of: "{MEDICATION_LIST}",
                with: "Active medications: \(medList)"
            )
        } else {
            extractionPrompt = extractionPrompt.replacingOccurrences(
                of: "{MEDICATION_LIST}",
                with: ""
            )
        }

        let result: ExtractionResult?
        do {
            let jsonDict = try await geminiService.sendStructuredRequest(
                text: conversationText,
                systemInstruction: extractionPrompt,
                jsonSchema: ExtractionResult.geminiSchema
            )
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
            result = try JSONDecoder().decode(ExtractionResult.self, from: jsonData)
        } catch {
            print("[LiveCheckInManager] Extraction failed: \(error)")
            return nil
        }

        guard let result else { return nil }

        print("[LiveCheckInManager] Extraction: covered=\(result.topicsCovered ?? []), notYetCovered=\(result.topicsNotYetCovered ?? []), action=\(result.recommendedAction ?? "nil")")

        // Apply to check-in
        if var checkIn = currentCheckIn {
            result.applyToCheckIn(&checkIn)
            currentCheckIn = checkIn
        }

        // Update vocabulary
        if let vocabUpdate = result.buildVocabularyUpdate() {
            vocabularyMap.merge(new: vocabUpdate)
        }

        // Track uncovered topics — only update if extraction explicitly provides the field.
        // If nil, keep the existing list (extraction may have omitted it).
        if let notYetCovered = result.topicsNotYetCovered {
            uncoveredTopics = notYetCovered
        } else if let covered = result.topicsCovered, !covered.isEmpty {
            // Fallback: compute remaining from what's been covered
            let allTopics = ["mood", "sleep", "symptoms", "medication"]
            uncoveredTopics = allTopics.filter { !covered.contains($0) }
        }

        lastExtraction = result
        return result
    }

    // MARK: - Private — Persistence

    private func loadContext() async {
        guard let sessionStore else { return }

        do {
            let context = try await sessionStore.loadContext(userId: userId)
            profile = context.profile
            recentCheckIns = context.recentCheckIns
            medications = context.medications
            if let vocab = context.vocabularyMap {
                vocabularyMap = vocab
            }
        } catch {
            print("[LiveCheckInManager] Error loading context: \(error)")
        }
    }

    private func autosave() async {
        guard let sessionStore else { return }

        do {
            if let checkIn = currentCheckIn {
                let docId = try await sessionStore.save(checkIn: checkIn, userId: userId)
                if currentCheckIn?.id == nil || currentCheckIn?.id?.isEmpty == true {
                    currentCheckIn?.id = docId
                }
                if transcriptDocument == nil, let currentCheckIn {
                    transcriptDocument = makeTranscript(for: currentCheckIn)
                }
                if var transcriptDocument {
                    if transcriptDocument.id == nil || transcriptDocument.id?.isEmpty == true {
                        transcriptDocument.id = currentCheckIn?.id
                    }
                    self.transcriptDocument = transcriptDocument
                    _ = try await sessionStore.save(transcript: transcriptDocument, userId: userId)
                }
            }
        } catch {
            print("[LiveCheckInManager] Autosave error: \(error)")
        }
    }

    private func saveVocabulary() async {
        guard let sessionStore else { return }

        do {
            _ = try await sessionStore.save(vocabularyMap: vocabularyMap, userId: userId)
        } catch {
            print("[LiveCheckInManager] Error saving vocabulary: \(error)")
        }
    }

    private func restoreActiveSession(type: CheckInType) async -> Bool {
        guard let sessionStore else { return false }

        do {
            guard let existingCheckIn = try await sessionStore.loadMostRecentInProgressCheckIn(
                userId: userId,
                type: type
            ) else {
                return false
            }

            currentCheckIn = existingCheckIn
            recentCheckIns.removeAll { $0.id == existingCheckIn.id }

            if let checkInId = existingCheckIn.id {
                let savedEvents = try await sessionStore.loadSessionEvents(userId: userId, sessionId: checkInId)
                nextEventSequence = (savedEvents.last?.sequenceNumber ?? -1) + 1

                if let savedTranscript = try await sessionStore.loadTranscript(userId: userId, checkInId: checkInId) {
                    transcriptDocument = savedTranscript
                    transcript = savedTranscript.entries.map { ($0.role.rawValue, $0.text) }
                } else if !savedEvents.isEmpty {
                    let rebuiltTranscript = rebuildTranscript(from: savedEvents, checkInId: checkInId)
                    transcriptDocument = rebuiltTranscript
                    transcript = rebuiltTranscript.entries.map { ($0.role.rawValue, $0.text) }
                } else {
                    var transcript = Transcript(checkInId: checkInId)
                    transcript.id = checkInId
                    transcriptDocument = transcript
                    self.transcript = []
                }
            }

            sessionStore.markStartMode(.resumed)
            return true
        } catch {
            print("[LiveCheckInManager] Resume failed: \(error)")
            return false
        }
    }

    private func appendTranscriptEntry(role: TranscriptRole, text: String) {
        guard var transcriptDocument else {
            if let currentCheckIn {
                var freshTranscript = makeTranscript(for: currentCheckIn)
                freshTranscript.addEntry(role: role, text: text)
                transcriptDocument = freshTranscript
                scheduleAutosave()
            }
            return
        }

        transcriptDocument.addEntry(role: role, text: text)
        self.transcriptDocument = transcriptDocument
        scheduleAutosave()
    }

    private func upsertTranscript(role: TranscriptRole, text: String) {
        let roleString = role.rawValue

        if let lastRole = transcript.last?.role, lastRole == roleString {
            transcript[transcript.count - 1].text = text
        } else {
            transcript.append((role: roleString, text: text))
        }

        guard var transcriptDocument else {
            if let currentCheckIn {
                var freshTranscript = makeTranscript(for: currentCheckIn)
                freshTranscript.addEntry(role: role, text: text)
                transcriptDocument = freshTranscript
                scheduleAutosave()
            }
            return
        }

        if let lastEntry = transcriptDocument.entries.last, lastEntry.role == role {
            transcriptDocument.entries[transcriptDocument.entries.count - 1] = TranscriptEntry(
                role: role,
                text: text,
                timestamp: lastEntry.timestamp
            )
        } else {
            transcriptDocument.addEntry(role: role, text: text)
        }
        transcriptDocument.entryCount = transcriptDocument.entries.count
        self.transcriptDocument = transcriptDocument
        if role == .user {
            pendingTurnUserEventText = text
        } else if role == .assistant {
            pendingTurnAssistantEventText = text
        }
        scheduleAutosave()
    }

    private func makeTranscript(for checkIn: CheckIn) -> Transcript {
        let checkInId = checkIn.id ?? UUID().uuidString
        var transcript = Transcript(checkInId: checkInId)
        transcript.id = checkInId
        return transcript
    }

    private func scheduleAutosave() {
        schedulePersistence()
    }

    private func schedulePersistence(
        sessionEvents: [CompanionSessionEvent] = [],
        outboxItems: [CompanionProjectionOutboxItem] = []
    ) {
        let previousTask = pendingAutosaveTask
        pendingAutosaveTask = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.persist(sessionEvents: sessionEvents, outboxItems: outboxItems)
        }
    }

    private func persist(
        sessionEvents: [CompanionSessionEvent] = [],
        outboxItems: [CompanionProjectionOutboxItem] = [],
        includeAutosave: Bool = true
    ) async {
        if let sessionStore {
            do {
                for event in sessionEvents {
                    _ = try await sessionStore.append(sessionEvent: event, userId: userId)
                }
                for outboxItem in outboxItems {
                    _ = try await sessionStore.save(outboxItem: outboxItem, userId: userId)
                }
            } catch {
                print("[LiveCheckInManager] Event persistence error: \(error)")
            }
        }
        if includeAutosave {
            await autosave()
        }
    }

    private func makeSessionEvent(
        type: CompanionSessionEventType,
        text: String? = nil,
        metadata: [String: String]? = nil
    ) -> CompanionSessionEvent? {
        guard let sessionId = currentCheckIn?.id else { return nil }
        let event = CompanionSessionEvent(
            sessionId: sessionId,
            sequenceNumber: nextEventSequence,
            type: type,
            source: "live",
            text: text,
            metadata: metadata,
            evidenceRef: currentCheckIn?.id
        )
        nextEventSequence += 1
        return event
    }

    private func makeProjectionOutboxItems() -> [CompanionProjectionOutboxItem] {
        guard let sessionId = currentCheckIn?.id else { return [] }
        let memoryPayloadJSON = MemoryProjectionService.makePayloadJSON(
            sessionId: sessionId,
            source: "live",
            intent: currentCheckIn?.type.rawValue,
            transcript: transcript
        )
        let graphPayloadJSON: String?
        if let checkIn = currentCheckIn, let extraction = lastExtraction {
            graphPayloadJSON = GraphSyncService.makePayloadJSON(
                checkIn: checkIn,
                extraction: extraction,
                eventId: GraphSyncService.makeEventId(sessionId: sessionId)
            )
        } else {
            graphPayloadJSON = nil
        }
        return [
            CompanionProjectionOutboxItem(
                sessionId: sessionId,
                kind: .memoryProjection,
                evidenceRef: sessionId,
                payloadJSON: memoryPayloadJSON
            ),
            CompanionProjectionOutboxItem(
                sessionId: sessionId,
                kind: .graphSync,
                evidenceRef: sessionId,
                payloadJSON: graphPayloadJSON
            )
        ]
    }

    private func rebuildTranscript(
        from sessionEvents: [CompanionSessionEvent],
        checkInId: String
    ) -> Transcript {
        var transcript = Transcript(checkInId: checkInId)
        transcript.id = checkInId
        transcript.entries = sessionEvents.compactMap { event in
            switch event.type {
            case .userUtterance:
                guard let text = event.text else { return nil }
                return TranscriptEntry(role: .user, text: text, timestamp: event.occurredAt)
            case .assistantUtterance:
                guard let text = event.text else { return nil }
                return TranscriptEntry(role: .assistant, text: text, timestamp: event.occurredAt)
            default:
                return nil
            }
        }
        transcript.entryCount = transcript.entries.count
        return transcript
    }

    private func shouldTreatOpeningGreetingAsOpening() -> Bool {
        guard transcript.count == 1 else { return false }
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

    // MARK: - Errors

    enum LiveCheckInError: Error, LocalizedError {
        case alreadyActive

        var errorDescription: String? {
            switch self {
            case .alreadyActive: return "A Live check-in is already in progress"
            }
        }
    }
}
