import Foundation

// MARK: - Check-In State

enum CheckInState: String {
    case idle
    case greeting
    case openResponse
    case extracting
    case followUp
    case medicationCheck
    case confirming
    case closing
    case completed
}

// MARK: - Check-In Service

/// State machine managing the check-in flow. Drives natural conversation,
/// extracts structured data silently, and manages progressive follow-ups.
final class CheckInService {

    // MARK: - State

    private(set) var state: CheckInState = .idle
    private(set) var currentCheckIn: CheckIn?
    private(set) var transcript: Transcript?
    private(set) var vocabularyMap: VocabularyMap
    private(set) var followUpCount: Int = 0

    // MARK: - Dependencies

    private let provider: CompanionProvider
    private let geminiService: GeminiService
    private let storageService: StorageService?
    private let graphSyncService: GraphSyncService?
    private let userId: String
    private let maxFollowUps: Int
    private let companionName: String

    // MARK: - Context Data

    private var profile: UserProfile?
    private var recentCheckIns: [CheckIn] = []
    private var medications: [Medication] = []
    private var messages: [CompanionMessage] = []
    private var uncoveredTopics: [String] = []
    private var lastRecommendedAction: String?
    private var lastEmotion: String?
    private var lastExtraction: ExtractionResult?

    // MARK: - Init

    init(
        provider: CompanionProvider,
        geminiService: GeminiService = GeminiService(),
        storageService: StorageService? = nil,
        graphSyncService: GraphSyncService? = nil,
        userId: String,
        maxFollowUps: Int = 5,
        companionName: String = "Mira"
    ) {
        self.provider = provider
        self.geminiService = geminiService
        self.storageService = storageService
        self.graphSyncService = graphSyncService
        self.userId = userId
        self.maxFollowUps = maxFollowUps
        self.companionName = companionName
        self.vocabularyMap = VocabularyMap()
    }

    // MARK: - Start Check-In

    /// Starts a new check-in. Loads context, creates records, generates greeting.
    func startCheckIn(type: CheckInType) async throws -> String {
        guard state == .idle else {
            throw CheckInServiceError.alreadyActive
        }

        // Load context
        await loadContext()

        // Create check-in record
        var checkIn = CheckIn(userId: userId, type: type)
        checkIn.checkInNumber = (recentCheckIns.first?.checkInNumber ?? 0) + 1
        self.currentCheckIn = checkIn

        // Create transcript
        self.transcript = Transcript(checkInId: checkIn.id ?? UUID().uuidString)

        // Build system prompt with context
        let basePrompt = PromptService.companionSystemPrompt
        let context = CompanionContext.build(
            profile: profile,
            recentCheckIns: recentCheckIns,
            medications: medications,
            vocabulary: vocabularyMap,
            companionName: companionName
        )
        let systemPrompt = "\(basePrompt)\n\n\(context)"

        // Add system message
        let systemMessage = CompanionMessage(role: .system, content: systemPrompt)
        messages = [systemMessage]

        // Transition to greeting
        transition(to: .greeting)

        // Generate greeting with context hints
        let greetingContext = CompanionContext.buildGreetingContext(
            recentCheckIns: recentCheckIns,
            userName: profile?.displayName,
            checkInType: type
        )
        let greetingPrompt = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Generate a warm, context-aware greeting. \(greetingContext) Keep it to 1-2 sentences.]"
        )
        messages.append(greetingPrompt)

        let greeting = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.8
        )

        // Replace the system instruction with the actual greeting in message history
        messages.removeLast()
        let assistantMessage = CompanionMessage(role: .assistant, content: greeting)
        messages.append(assistantMessage)
        transcript?.addEntry(role: .assistant, text: greeting)

        // Autosave
        await autosave()

        transition(to: .openResponse)
        return greeting
    }

    // MARK: - Process User Input

    /// Routes user speech through the state-appropriate handler.
    func processUserInput(_ text: String) async throws -> String {
        guard state != .idle && state != .completed else {
            throw CheckInServiceError.notActive
        }

        // Record user input
        let userMessage = CompanionMessage(role: .user, content: text)
        messages.append(userMessage)
        transcript?.addEntry(role: .user, text: text)

        let response: String

        switch state {
        case .openResponse, .followUp:
            response = try await handleConversationalInput(text)
        case .medicationCheck:
            response = try await handleMedicationResponse(text)
        case .confirming:
            response = try await handleConfirmation(text)
        case .closing:
            response = try await handleClosing(text)
        default:
            response = try await handleConversationalInput(text)
        }

        // Record assistant response
        let assistantMessage = CompanionMessage(role: .assistant, content: response)
        messages.append(assistantMessage)
        transcript?.addEntry(role: .assistant, text: response)

        // Autosave after every exchange
        await autosave()

        return response
    }

    // MARK: - Cancel

    /// Cancels the current check-in, saving partial data.
    func cancelCheckIn() async {
        guard state != .idle && state != .completed else { return }

        currentCheckIn?.completionStatus = .abandoned
        currentCheckIn?.completedAt = Date()
        if let startedAt = currentCheckIn?.startedAt {
            currentCheckIn?.durationSeconds = Int(Date().timeIntervalSince(startedAt))
        }

        await autosave()
        reset()
    }

    // MARK: - Conversation Handlers

    private func handleConversationalInput(_ text: String) async throws -> String {
        // Run extraction — returns guidance fields
        transition(to: .extracting)
        let result = try await runExtraction()

        let action = result?.recommendedAction ?? "ask"
        let allTopicsCovered = uncoveredTopics.isEmpty

        // Hard close: model says close OR hit follow-up limit
        if action == "close" || followUpCount >= maxFollowUps {
            if !medications.isEmpty && currentCheckIn?.medicationAdherence.isEmpty == true {
                transition(to: .medicationCheck)
                return try await generateMedicationCheck()
            }
            transition(to: .confirming)
            return try await generateConfirmation()
        }

        // Soft close: all topics covered and no emotional content to address
        if allTopicsCovered && action != "reflect" && action != "affirm" {
            if !medications.isEmpty && currentCheckIn?.medicationAdherence.isEmpty == true {
                transition(to: .medicationCheck)
                return try await generateMedicationCheck()
            }
            transition(to: .confirming)
            return try await generateConfirmation()
        }

        // Dispatch on recommended action
        transition(to: .followUp)
        followUpCount += 1

        switch action {
        case "reflect":
            return try await generateReflection()
        case "affirm":
            return try await generateAffirmation()
        case "summarize":
            return try await generateMidSummary()
        case "ask":
            return try await generateFollowUp()
        default:
            // Emotion-based heuristic fallback
            let distressedEmotions = ["frustrated", "anxious", "sad", "in_pain"]
            if let emotion = result?.emotion, distressedEmotions.contains(emotion) {
                return try await generateReflection()
            }
            return try await generateFollowUp()
        }
    }

    private func handleMedicationResponse(_ text: String) async throws -> String {
        // Re-extract to capture medication info
        try await runExtraction()

        transition(to: .confirming)
        return try await generateConfirmation()
    }

    private func handleConfirmation(_ text: String) async throws -> String {
        let lower = text.lowercased()

        // Check if user wants to correct something
        let correctionKeywords = ["no", "not right", "actually", "wrong", "change", "correct"]
        let isCorrection = correctionKeywords.contains { lower.contains($0) }

        if isCorrection {
            // Re-extract with correction context
            try await runExtraction()
            return try await generateConfirmation()
        }

        // User confirmed — play confirmation feedback and close
        HapticService.confirmationAccepted()
        AudioCueService.playAcknowledgment()
        transition(to: .closing)
        return try await generateClose()
    }

    private func handleClosing(_ text: String) async throws -> String {
        // Finalize
        await completeCheckIn()
        return "" // Closing message was already generated
    }

    // MARK: - Response Generators

    private func generateFollowUp() async throws -> String {
        guard let topic = uncoveredTopics.first else {
            transition(to: .confirming)
            return try await generateConfirmation()
        }

        let systemPrompt = buildCurrentSystemPrompt()
        let followUpInstruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Gently ask about \(topic). Use natural language, not a questionnaire. Reference what the member already shared. One question only, 1-2 sentences.]"
        )
        messages.append(followUpInstruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.7
        )

        messages.removeLast() // remove the system instruction
        return response
    }

    private func generateReflection() async throws -> String {
        let systemPrompt = buildCurrentSystemPrompt()
        let instruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Reflect back what the member just shared. Show you truly heard them. Mirror their words or feelings in your own words. Do NOT ask a new question. 1-2 sentences.]"
        )
        messages.append(instruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.7
        )

        messages.removeLast()
        return response
    }

    private func generateAffirmation() async throws -> String {
        let systemPrompt = buildCurrentSystemPrompt()
        let instruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Affirm and celebrate the effort or win the member just shared. Be genuine, not patronizing. You may include one gentle follow-up question if it flows naturally, but it's not required. 1-2 sentences.]"
        )
        messages.append(instruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.7
        )

        messages.removeLast()
        return response
    }

    private func generateMidSummary() async throws -> String {
        let systemPrompt = buildCurrentSystemPrompt()
        let coveredSummary = buildCheckInSummary()
        let remaining = uncoveredTopics.isEmpty ? "nothing" : uncoveredTopics.joined(separator: ", ")

        let instruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Weave together what the member has shared so far: \(coveredSummary). Use a warm, conversational tone — not a list. If there are uncovered topics (\(remaining)), transition naturally toward one. Otherwise, ask if there's anything else on their mind. 2-3 sentences.]"
        )
        messages.append(instruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.7
        )

        messages.removeLast()
        return response
    }

    private func generateMedicationCheck() async throws -> String {
        let systemPrompt = buildCurrentSystemPrompt()
        let activeMeds = medications.filter { $0.isActive }
        let medNames = activeMeds.map { med -> String in
            if let nickname = vocabularyMap.medicationNicknames.first(where: { $0.value == med.id })?.key {
                return nickname
            }
            return med.name
        }

        let medList = medNames.joined(separator: ", ")
        let instruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Ask if the member took their medications today. Medications: \(medList). Use casual language and the member's nicknames if available. One question, 1-2 sentences.]"
        )
        messages.append(instruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.7
        )

        messages.removeLast()
        return response
    }

    private func generateConfirmation() async throws -> String {
        let systemPrompt = buildCurrentSystemPrompt()
        let summary = buildCheckInSummary()

        let instruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: Summarize what you heard from the member: \(summary). Ask if that sounds right. Keep it brief and warm. Use the member's own words where possible.]"
        )
        messages.append(instruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.7
        )

        messages.removeLast()
        return response
    }

    private func generateClose() async throws -> String {
        let systemPrompt = buildCurrentSystemPrompt()

        let closingContext = CompanionContext.buildClosingContext(
            currentCheckIn: currentCheckIn,
            recentCheckIns: recentCheckIns
        )
        let instruction = CompanionMessage(
            role: .user,
            content: "[SYSTEM: \(closingContext) Don't ask any more questions.]"
        )
        messages.append(instruction)

        let response = try await provider.generateResponse(
            messages: messages,
            systemPrompt: systemPrompt,
            temperature: 0.8
        )

        messages.removeLast()

        // Finalize
        await completeCheckIn()

        return response
    }

    // MARK: - Extraction

    @discardableResult
    private func runExtraction() async throws -> ExtractionResult? {
        let conversationText = messages
            .filter { $0.role != .system }
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")

        // Build extraction prompt with medication context
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

        // Try structured output first, fall back to provider.extractHealthData
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
            print("[CheckInService] Structured extraction failed, falling back: \(error)")
            let jsonString = try await provider.extractHealthData(
                conversationText: conversationText,
                extractionPrompt: extractionPrompt
            )
            guard let jsonData = jsonString.data(using: .utf8) else { return nil }
            result = try? JSONDecoder().decode(ExtractionResult.self, from: jsonData)
        }

        guard let result else {
            print("[CheckInService] Failed to decode extraction result")
            return nil
        }

        // Apply to check-in
        if var checkIn = currentCheckIn {
            result.applyToCheckIn(&checkIn)
            self.currentCheckIn = checkIn
        }

        // Update vocabulary
        if let vocabUpdate = result.buildVocabularyUpdate() {
            vocabularyMap.merge(new: vocabUpdate)
        }

        // Track uncovered topics
        uncoveredTopics = result.topicsNotYetCovered ?? []

        // Track conversation guidance
        lastRecommendedAction = result.recommendedAction
        lastEmotion = result.emotion

        // Store for graph sync on completion
        lastExtraction = result

        return result
    }

    // MARK: - Persistence

    private func loadContext() async {
        guard let storage = storageService else { return }

        do {
            // Load profile
            profile = try await storage.fetch(
                UserProfile.self,
                from: "profile",
                userId: userId,
                documentId: "main"
            )

            // Load recent check-ins (last 5)
            recentCheckIns = try await storage.fetchAll(
                CheckIn.self,
                from: "checkins",
                userId: userId,
                limit: 5
            )

            // Load active medications
            medications = try await storage.fetchAll(
                Medication.self,
                from: "medications",
                userId: userId
            )

            // Load vocabulary
            if let vocab = try await storage.fetch(
                VocabularyMap.self,
                from: "profile",
                userId: userId,
                documentId: "vocabulary"
            ) {
                vocabularyMap = vocab
            }
        } catch {
            print("[CheckInService] Error loading context: \(error)")
        }
    }

    private func autosave() async {
        guard let storage = storageService else { return }

        do {
            let enc = storage.encryptionService
            let key = try enc.getOrCreateKey(for: userId)

            // Save check-in (encrypt sensitive fields before writing)
            if var checkIn = currentCheckIn {
                var toSave = checkIn
                try toSave.encryptFields(using: enc, key: key)
                let docId = try await storage.save(
                    toSave,
                    to: "checkins",
                    userId: userId,
                    documentId: checkIn.id
                )
                if currentCheckIn?.id == nil {
                    currentCheckIn?.id = docId
                }
            }

            // Save transcript (encrypt entry text before writing)
            if var transcript = transcript {
                var toSave = transcript
                try toSave.encryptFields(using: enc, key: key)
                let docId = try await storage.save(
                    toSave,
                    to: "transcripts",
                    userId: userId,
                    documentId: transcript.id
                )
                if self.transcript?.id == nil {
                    self.transcript?.id = docId
                }
            }
        } catch {
            print("[CheckInService] Autosave error: \(error)")
        }
    }

    private func completeCheckIn() async {
        currentCheckIn?.completionStatus = .completed
        currentCheckIn?.completedAt = Date()
        if let startedAt = currentCheckIn?.startedAt {
            currentCheckIn?.durationSeconds = Int(Date().timeIntervalSince(startedAt))
        }

        // Save vocabulary
        if let storage = storageService {
            do {
                _ = try await storage.save(
                    vocabularyMap,
                    to: "profile",
                    userId: userId,
                    documentId: "vocabulary"
                )
            } catch {
                print("[CheckInService] Error saving vocabulary: \(error)")
            }
        }

        await autosave()

        // Generate AI summary — non-blocking, failure must not block completion
        do {
            let conversationText = messages
                .filter { $0.role != .system }
                .map { "\($0.role.rawValue): \($0.content)" }
                .joined(separator: "\n")
            if !conversationText.isEmpty {
                let prompt = "Summarize this wellness check-in in under 20 words. State only facts mentioned: mood, sleep hours, symptoms, medications. No filler.\n\nConversation:\n\(conversationText)"
                let summary = try await geminiService.sendTextRequest(text: prompt)
                currentCheckIn?.aiSummary = summary
                await autosave()
            }
        } catch {
            print("[CheckInService] AI summary generation failed (non-blocking): \(error)")
        }

        // Sync to backend graph — fire-and-forget, failures must not block the user
        if let checkIn = currentCheckIn, let extraction = lastExtraction {
            Task {
                await graphSyncService?.syncCheckIn(checkIn, extraction: extraction)
            }
        }

        transition(to: .completed)
    }

    // MARK: - Helpers

    private func transition(to newState: CheckInState) {
        print("[CheckInService] \(state.rawValue) → \(newState.rawValue)")
        state = newState
    }

    private func buildCurrentSystemPrompt() -> String {
        let basePrompt = PromptService.companionSystemPrompt
        let context = CompanionContext.build(
            profile: profile,
            recentCheckIns: recentCheckIns,
            medications: medications,
            vocabulary: vocabularyMap,
            companionName: companionName
        )
        return "\(basePrompt)\n\n\(context)"
    }

    private func buildCheckInSummary() -> String {
        guard let checkIn = currentCheckIn else { return "nothing yet" }

        var parts: [String] = []
        if let mood = checkIn.mood?.description {
            parts.append("mood: \(mood)")
        }
        if let sleep = checkIn.sleep {
            if let hours = sleep.hours {
                parts.append("sleep: \(hours) hours")
            }
        }
        for symptom in checkIn.symptoms {
            let desc = symptom.userDescription ?? symptom.type.rawValue
            parts.append(desc)
        }
        for med in checkIn.medicationAdherence {
            parts.append("\(med.medicationName): \(med.status.rawValue)")
        }
        return parts.isEmpty ? "a general check-in" : parts.joined(separator: ", ")
    }

    private func reset() {
        state = .idle
        currentCheckIn = nil
        transcript = nil
        messages = []
        followUpCount = 0
        uncoveredTopics = []
        lastRecommendedAction = nil
        lastEmotion = nil
        lastExtraction = nil
    }

    // MARK: - Errors

    enum CheckInServiceError: Error, LocalizedError {
        case alreadyActive
        case notActive

        var errorDescription: String? {
            switch self {
            case .alreadyActive: return "A check-in is already in progress"
            case .notActive: return "No check-in is currently active"
            }
        }
    }
}
