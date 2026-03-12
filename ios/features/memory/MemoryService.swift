import Foundation

/// Manages cross-session memory: episodic events, semantic patterns, procedural rules.
/// Loads from Firestore, builds context strings for prompt injection, extracts new memories
/// from session transcripts via Gemini, and consolidates (decay, merge, prune).
@MainActor
final class MemoryService {

    // MARK: - Dependencies

    private let storageService: StorageService?
    private let geminiService: GeminiService?
    private let userId: String

    // MARK: - State

    var episodicMemories: [EpisodicMemory] = []
    var semanticPatterns: [SemanticPattern] = []
    var proceduralRules: [ProceduralRule] = []
    var profile: UserProfile?

    // MARK: - Init

    init(storageService: StorageService?, geminiService: GeminiService?, userId: String) {
        self.storageService = storageService
        self.geminiService = geminiService
        self.userId = userId
    }

    // MARK: - Load

    func loadMemories() async {
        guard let storage = storageService else { return }

        do {
            profile = try await storage.fetch(
                UserProfile.self,
                from: "profile",
                userId: userId,
                documentId: "main"
            )

            if let episodic: MemoryDocument<EpisodicMemory> = try await storage.fetch(
                MemoryDocument<EpisodicMemory>.self,
                from: "memory",
                userId: userId,
                documentId: "episodic"
            ) {
                episodicMemories = episodic.items
            }

            if let semantic: MemoryDocument<SemanticPattern> = try await storage.fetch(
                MemoryDocument<SemanticPattern>.self,
                from: "memory",
                userId: userId,
                documentId: "semantic"
            ) {
                semanticPatterns = semantic.items
            }

            if let procedural: MemoryDocument<ProceduralRule> = try await storage.fetch(
                MemoryDocument<ProceduralRule>.self,
                from: "memory",
                userId: userId,
                documentId: "procedural"
            ) {
                proceduralRules = procedural.items
            }
        } catch {
            print("[MemoryService] Error loading memories: \(error)")
        }
    }

    // MARK: - Build Context String

    func buildContextString() -> String {
        var sections: [String] = []

        // Profile section
        let profileSection = buildProfileSection()
        if !profileSection.isEmpty {
            sections.append(profileSection)
        }

        // Recent sessions (episodic)
        let episodicSection = buildEpisodicSection()
        if !episodicSection.isEmpty {
            sections.append(episodicSection)
        }

        // Known facts (semantic)
        let semanticSection = buildSemanticSection()
        if !semanticSection.isEmpty {
            sections.append(semanticSection)
        }

        // Behavioral rules (procedural)
        let proceduralSection = buildProceduralSection()
        if !proceduralSection.isEmpty {
            sections.append(proceduralSection)
        }

        // Current moment
        let momentSection = buildMomentSection()
        sections.append(momentSection)

        let context = sections.joined(separator: "\n\n")

        // Trim to budget if needed
        let tokens = MemoryBudget.estimateTokens(context)
        if tokens > MemoryBudget.totalBudget {
            return trimToTokenBudget(context)
        }
        return context
    }

    func recallResponse(for userText: String) -> String? {
        guard let matchedMemory = matchedRecallMemory(for: userText) else { return nil }
        return recallResponse(from: matchedMemory)
    }

    // MARK: - Effective Importance

    func effectiveImportance(_ memory: EpisodicMemory, asOf date: Date = Date()) -> Double {
        let daysSince = date.timeIntervalSince(memory.timestamp) / 86400
        let sourceAdjustedDecay = memory.decayRate + (memory.source == "casual" ? 0.05 : 0.0)
        return memory.importance * exp(-sourceAdjustedDecay * daysSince)
    }

    // MARK: - Extract Memories from Transcript

    func extractMemories(transcript: [(role: String, text: String)]) async -> MemoryDelta? {
        let outcome = await extractProjectionOutcome(transcript: transcript)
        return outcome.delta
    }

    func extractProjectionOutcome(
        transcript: [(role: String, text: String)]
    ) async -> MemoryExtractionOutcome {
        guard !transcript.isEmpty else {
            return MemoryExtractionOutcome(delta: nil, llmAttempted: false, llmSucceeded: false)
        }

        let conversationText = transcript
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n")

        var mergedDelta = MemoryDelta(
            episodicAdds: [],
            semanticUpdates: [],
            proceduralUpdates: []
        )

        let prompt = """
        Analyze this conversation and extract memory updates. Return structured JSON.

        For episodic: summarize the session in 1-2 sentences, note the dominant emotion, \
        list topics covered, and explicitly preserve recent concrete details the person may refer back to soon \
        (what they are eating, drinking, watching, reading, listening to, making, or generating). \
        Rate importance (health facts = 1.0, personal sharing = 0.7, recent concrete details = 0.65, \
        small talk = 0.3), set decay rate (health = 0.0, personal = 0.1, recent details = 0.12, small talk = 0.3).

        For semantic: extract or update lasting facts about the person \
        (sleep patterns, preferences, routines, health observations). \
        Set confidence based on how explicitly stated (direct statement = 0.9, implied = 0.5).

        For procedural: note any behavioral preferences the person expressed \
        (e.g., "don't ask about X", "I prefer short answers", "stop means stop").

        Conversation:
        \(conversationText)
        """

        var llmAttempted = false
        var llmSucceeded = false

        if let gemini = geminiService {
            llmAttempted = true
            do {
                let jsonDict = try await gemini.sendStructuredRequest(
                    text: prompt,
                    systemInstruction: "Extract memory updates from the conversation. Return only the structured data.",
                    jsonSchema: MemoryDelta.geminiSchema
                )
                let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
                mergedDelta = try JSONDecoder().decode(MemoryDelta.self, from: jsonData)
                llmSucceeded = true
            } catch {
                print("[MemoryService] Memory extraction failed: \(error)")
            }
        }

        let supplementalMemories = supplementRecentDetailMemories(from: transcript)
        for memory in supplementalMemories where !containsEquivalentEpisodicMemory(memory, in: mergedDelta.episodicAdds) {
            mergedDelta.episodicAdds.append(memory)
        }

        let hasChanges = !mergedDelta.episodicAdds.isEmpty
            || !mergedDelta.semanticUpdates.isEmpty
            || !mergedDelta.proceduralUpdates.isEmpty
        return MemoryExtractionOutcome(
            delta: hasChanges ? mergedDelta : nil,
            llmAttempted: llmAttempted,
            llmSucceeded: llmSucceeded
        )
    }

    // MARK: - Apply Delta

    func applyDelta(_ delta: MemoryDelta) async {
        // Add new episodic memories
        for memory in delta.episodicAdds {
            guard !containsEquivalentEpisodicMemory(memory, in: episodicMemories) else { continue }
            episodicMemories.append(memory)
        }

        // Process semantic updates
        for update in delta.semanticUpdates {
            switch update.op {
            case .add:
                if let existingIndex = semanticPatterns.firstIndex(where: { existing in
                    existing.category == update.pattern.category
                        && normalizedMemoryText(existing.fact) == normalizedMemoryText(update.pattern.fact)
                }) {
                    semanticPatterns[existingIndex].confidence = max(
                        semanticPatterns[existingIndex].confidence,
                        update.pattern.confidence
                    )
                    semanticPatterns[existingIndex].lastConfirmed = max(
                        semanticPatterns[existingIndex].lastConfirmed,
                        update.pattern.lastConfirmed
                    )
                } else {
                    semanticPatterns.append(update.pattern)
                }
            case .update:
                if let id = update.id,
                   let index = semanticPatterns.firstIndex(where: { $0.id == id }) {
                    semanticPatterns[index].fact = update.pattern.fact
                    semanticPatterns[index].confidence = update.pattern.confidence
                    semanticPatterns[index].lastConfirmed = Date()
                } else {
                    // ID not found — treat as add
                    semanticPatterns.append(update.pattern)
                }
            case .delete:
                if let id = update.id {
                    semanticPatterns.removeAll { $0.id == id }
                }
            case .noop:
                break
            }
        }

        // Process procedural updates
        for update in delta.proceduralUpdates {
            switch update.op {
            case .add:
                guard !proceduralRules.contains(where: {
                    $0.trigger.caseInsensitiveCompare(update.rule.trigger) == .orderedSame
                        && $0.action.caseInsensitiveCompare(update.rule.action) == .orderedSame
                }) else { continue }
                proceduralRules.append(update.rule)
            case .update:
                if let id = update.id,
                   let index = proceduralRules.firstIndex(where: { $0.id == id }) {
                    proceduralRules[index].action = update.rule.action
                }
            case .delete:
                if let id = update.id {
                    proceduralRules.removeAll { $0.id == id }
                }
            case .noop:
                break
            }
        }

        await saveMemories()
    }

    // MARK: - Consolidate

    func consolidateMemories() async {
        // Decay: remove episodic memories below threshold
        let threshold = 0.05
        episodicMemories.removeAll { memory in
            effectiveImportance(memory) < threshold
        }

        // Merge duplicate semantic patterns (same category + similar fact)
        mergeDuplicateSemantics()

        // Cap episodic count to prevent unbounded growth
        let maxEpisodic = 50
        if episodicMemories.count > maxEpisodic {
            // Sort by effective importance, keep top N
            episodicMemories.sort { effectiveImportance($0) > effectiveImportance($1) }
            episodicMemories = Array(episodicMemories.prefix(maxEpisodic))
        }

        await saveMemories()
    }

    // MARK: - Private — Context Building

    private func buildProfileSection() -> String {
        var lines = ["[Who You're Talking To]"]
        if let name = profile?.displayName {
            lines.append("Name: \(name)")
        }
        if let profile = profile {
            lines.append("Week \(profile.weekNumber) of check-ins")
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    private func buildEpisodicSection() -> String {
        guard !episodicMemories.isEmpty else { return "" }

        var lines = ["[Recent Sessions]"]
        let sorted = episodicMemories
            .sorted { $0.timestamp > $1.timestamp }
            .filter { effectiveImportance($0) >= 0.05 }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        var tokenCount = 0
        for memory in sorted {
            let relTime = formatter.localizedString(for: memory.timestamp, relativeTo: Date())
            var line = "- \(relTime): \(memory.summary)"
            if let emotion = memory.emotion {
                line += " (feeling \(emotion))"
            }
            let lineTokens = MemoryBudget.estimateTokens(line)
            if tokenCount + lineTokens > MemoryBudget.maxEpisodicTokens { break }
            tokenCount += lineTokens
            lines.append(line)
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    private func buildSemanticSection() -> String {
        guard !semanticPatterns.isEmpty else { return "" }

        var lines = ["[What You Know About Them]"]
        let sorted = semanticPatterns.sorted { $0.confidence > $1.confidence }

        var tokenCount = 0
        for pattern in sorted {
            let line = "- [\(pattern.category)] \(pattern.fact) (confidence: \(String(format: "%.0f%%", pattern.confidence * 100)))"
            let lineTokens = MemoryBudget.estimateTokens(line)
            if tokenCount + lineTokens > MemoryBudget.maxSemanticTokens { break }
            tokenCount += lineTokens
            lines.append(line)
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    private func buildProceduralSection() -> String {
        guard !proceduralRules.isEmpty else { return "" }

        var lines = ["[How To Behave]"]
        var tokenCount = 0
        for rule in proceduralRules {
            let line = "- When \(rule.trigger): \(rule.action)"
            let lineTokens = MemoryBudget.estimateTokens(line)
            if tokenCount + lineTokens > MemoryBudget.maxProceduralTokens { break }
            tokenCount += lineTokens
            lines.append(line)
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    private func buildMomentSection() -> String {
        PromptService.buildRightNowContext()
    }

    private func trimToTokenBudget(_ text: String) -> String {
        let targetChars = MemoryBudget.totalBudget * 4
        if text.count <= targetChars { return text }
        return String(text.prefix(targetChars))
    }

    private enum RecallCategory {
        case food
        case drink
        case watch
        case read
        case listen
        case create
        case recentDetail
    }

    private func matchedRecallMemory(for userText: String) -> EpisodicMemory? {
        guard let category = recallCategory(for: userText) else { return nil }

        let sortedMemories = episodicMemories
            .filter { effectiveImportance($0) >= 0.05 }
            .sorted { $0.timestamp > $1.timestamp }

        return sortedMemories.first { memory in
            matchesRecallCategory(category, memory: memory)
        }
    }

    private func recallCategory(for userText: String) -> RecallCategory? {
        let normalized = normalizedMemoryText(userText)
        let recallSignals = [
            "remember",
            "earlier",
            "before",
            "what was i",
            "what did i",
            "did i mention",
            "do you know what i"
        ]
        guard recallSignals.contains(where: { normalized.contains($0) }) else { return nil }

        if normalized.contains("eat") || normalized.contains("food") {
            return .food
        }
        if normalized.contains("drink") {
            return .drink
        }
        if normalized.contains("watch") {
            return .watch
        }
        if normalized.contains("read") {
            return .read
        }
        if normalized.contains("listen") || normalized.contains("song") || normalized.contains("music") {
            return .listen
        }
        if normalized.contains("creat")
            || normalized.contains("generat")
            || normalized.contains("made")
            || normalized.contains("make")
            || normalized.contains("drew")
            || normalized.contains("draw")
            || normalized.contains("composed")
            || normalized.contains("recorded")
            || normalized.contains("video")
            || normalized.contains("image") {
            return .create
        }

        return .recentDetail
    }

    private func matchesRecallCategory(_ category: RecallCategory, memory: EpisodicMemory) -> Bool {
        let normalizedSummary = normalizedMemoryText(memory.summary)
        let topics = Set(memory.topicsCovered.map { normalizedMemoryText($0) })

        switch category {
        case .food:
            return topics.contains("food") || normalizedSummary.contains("were eating")
        case .drink:
            return topics.contains("drink") || normalizedSummary.contains("were drinking")
        case .watch:
            return normalizedSummary.contains("were watching")
        case .read:
            return normalizedSummary.contains("were reading")
        case .listen:
            return normalizedSummary.contains("were listening")
        case .create:
            return topics.contains("creation")
                || normalizedSummary.contains("generated")
                || normalizedSummary.contains("created")
                || normalizedSummary.contains("composed")
                || normalizedSummary.contains("recorded")
                || normalizedSummary.contains("drew")
        case .recentDetail:
            return topics.contains("recent detail") || memory.source == "recent_detail"
        }
    }

    private func recallResponse(from memory: EpisodicMemory) -> String {
        let summary = memory.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        if let remainder = summary.removingPrefix("They mentioned they were ") {
            return ensureSentence("Earlier you mentioned you were \(remainder)")
        }
        if let remainder = summary.removingPrefix("They said they ") {
            return ensureSentence("Earlier you mentioned you \(remainder)")
        }

        return ensureSentence("Earlier you mentioned \(summary)")
    }

    private func ensureSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return trimmed
        }
        return "\(trimmed)."
    }

    // MARK: - Private — Recent Detail Supplement

    private func supplementRecentDetailMemories(from transcript: [(role: String, text: String)]) -> [EpisodicMemory] {
        let userTurns = transcript
            .filter { $0.role == "user" }
            .suffix(6)

        var memories: [EpisodicMemory] = []
        var seen = Set<String>()

        for turn in userTurns {
            for detail in extractRecentDetails(from: turn.text) {
                let key = normalizedMemoryText(detail.summary)
                guard seen.insert(key).inserted else { continue }
                memories.append(detail)
            }
        }

        return memories
    }

    private func extractRecentDetails(from text: String) -> [EpisodicMemory] {
        struct DetailPattern {
            let regex: String
            let topics: [String]
            let importance: Double
            let decayRate: Double
            let summaryBuilder: (String, String) -> String
        }

        let patterns: [DetailPattern] = [
            DetailPattern(
                regex: #"(?i)\b(i am|i'm|im)\s+(eating)\s+(.+)"#,
                topics: ["food", "recent_detail"],
                importance: 0.65,
                decayRate: 0.12,
                summaryBuilder: { _, object in "They mentioned they were eating \(object)." }
            ),
            DetailPattern(
                regex: #"(?i)\b(i am|i'm|im)\s+(drinking)\s+(.+)"#,
                topics: ["drink", "recent_detail"],
                importance: 0.65,
                decayRate: 0.12,
                summaryBuilder: { _, object in "They mentioned they were drinking \(object)." }
            ),
            DetailPattern(
                regex: #"(?i)\b(i am|i'm|im)\s+(watching)\s+(.+)"#,
                topics: ["media", "recent_detail"],
                importance: 0.6,
                decayRate: 0.12,
                summaryBuilder: { _, object in "They mentioned they were watching \(object)." }
            ),
            DetailPattern(
                regex: #"(?i)\b(i am|i'm|im)\s+(reading)\s+(.+)"#,
                topics: ["media", "recent_detail"],
                importance: 0.6,
                decayRate: 0.12,
                summaryBuilder: { _, object in "They mentioned they were reading \(object)." }
            ),
            DetailPattern(
                regex: #"(?i)\b(i am|i'm|im)\s+listening\s+to\s+(.+)"#,
                topics: ["media", "recent_detail"],
                importance: 0.6,
                decayRate: 0.12,
                summaryBuilder: { _, object in "They mentioned they were listening to \(object)." }
            ),
            DetailPattern(
                regex: #"(?i)\b(?:i|we)(?:\s+just)?\s+(made|generated|created|drew|composed|recorded|cooked)\s+(.+)"#,
                topics: ["creation", "recent_detail"],
                importance: 0.75,
                decayRate: 0.1,
                summaryBuilder: { verb, object in "They said they \(verb) \(object)." }
            )
        ]

        let nsText = text as NSString
        var details: [EpisodicMemory] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex) else { continue }
            let fullRange = NSRange(location: 0, length: nsText.length)
            guard let match = regex.firstMatch(in: text, range: fullRange) else { continue }

            let verbIndex = match.numberOfRanges > 2 ? match.numberOfRanges - 2 : 1
            let objectIndex = match.numberOfRanges - 1
            let verb = nsText.substring(with: match.range(at: verbIndex)).lowercased()
            let rawObject = nsText.substring(with: match.range(at: objectIndex))
            guard let object = cleanRecentDetailObject(rawObject) else { continue }

            details.append(EpisodicMemory(
                timestamp: Date(),
                summary: pattern.summaryBuilder(verb, object),
                emotion: nil,
                topicsCovered: pattern.topics,
                importance: pattern.importance,
                decayRate: pattern.decayRate,
                source: "recent_detail"
            ))
        }

        return details
    }

    private func cleanRecentDetailObject(_ raw: String) -> String? {
        let firstClause = raw
            .components(separatedBy: CharacterSet(charactersIn: ".!?;,"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let stripped = firstClause
            .replacingOccurrences(of: #"(?i)\b(right now|at the moment|for now)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))

        guard !stripped.isEmpty else { return nil }
        let words = stripped.split(separator: " ")
        guard !words.isEmpty else { return nil }
        return words.count <= 12 ? stripped : words.prefix(12).joined(separator: " ")
    }

    private func containsEquivalentEpisodicMemory(_ candidate: EpisodicMemory, in existing: [EpisodicMemory]) -> Bool {
        let normalizedCandidate = normalizedMemoryText(candidate.summary)
        return existing.contains { memory in
            let normalizedExisting = normalizedMemoryText(memory.summary)
            return normalizedExisting == normalizedCandidate
                || normalizedExisting.contains(normalizedCandidate)
                || normalizedCandidate.contains(normalizedExisting)
        }
    }

    private func normalizedMemoryText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private — Merge

    private func mergeDuplicateSemantics() {
        var merged: [SemanticPattern] = []
        var seen: [String: Int] = [:]

        for pattern in semanticPatterns {
            let key = "\(pattern.category):\(pattern.fact.lowercased().prefix(50))"
            if let existingIndex = seen[key] {
                // Merge: increase confidence, update lastConfirmed
                merged[existingIndex].confidence = min(1.0, merged[existingIndex].confidence + 0.1)
                merged[existingIndex].lastConfirmed = max(merged[existingIndex].lastConfirmed, pattern.lastConfirmed)
            } else {
                seen[key] = merged.count
                merged.append(pattern)
            }
        }

        semanticPatterns = merged
    }

    // MARK: - Private — Persistence

    private func saveMemories() async {
        guard let storage = storageService else { return }

        do {
            _ = try await storage.save(
                MemoryDocument(items: episodicMemories),
                to: "memory",
                userId: userId,
                documentId: "episodic"
            )
            _ = try await storage.save(
                MemoryDocument(items: semanticPatterns),
                to: "memory",
                userId: userId,
                documentId: "semantic"
            )
            _ = try await storage.save(
                MemoryDocument(items: proceduralRules),
                to: "memory",
                userId: userId,
                documentId: "procedural"
            )
        } catch {
            print("[MemoryService] Error saving memories: \(error)")
        }
    }
}

// MARK: - Storage Wrapper

struct MemoryExtractionOutcome {
    let delta: MemoryDelta?
    let llmAttempted: Bool
    let llmSucceeded: Bool

    var shouldRetry: Bool {
        llmAttempted && !llmSucceeded
    }
}

struct MemoryDocument<T: Codable>: Codable {
    var items: [T]
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

// MARK: - Gemini Schema for Memory Extraction

extension MemoryDelta {
    static var geminiSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "episodicAdds": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "summary": ["type": "STRING"],
                            "emotion": ["type": "STRING"],
                            "topicsCovered": ["type": "ARRAY", "items": ["type": "STRING"]],
                            "importance": ["type": "NUMBER"],
                            "decayRate": ["type": "NUMBER"],
                            "source": ["type": "STRING"]
                        ] as [String: Any],
                        "required": ["summary", "topicsCovered", "importance", "decayRate", "source"]
                    ] as [String: Any]
                ] as [String: Any],
                "semanticUpdates": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "op": ["type": "STRING", "enum": ["add", "update", "delete", "noop"]],
                            "id": ["type": "STRING"],
                            "pattern": [
                                "type": "OBJECT",
                                "properties": [
                                    "category": ["type": "STRING"],
                                    "fact": ["type": "STRING"],
                                    "confidence": ["type": "NUMBER"],
                                    "source": ["type": "STRING"]
                                ] as [String: Any],
                                "required": ["category", "fact", "confidence", "source"]
                            ] as [String: Any]
                        ] as [String: Any],
                        "required": ["op"]
                    ] as [String: Any]
                ] as [String: Any],
                "proceduralUpdates": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "op": ["type": "STRING", "enum": ["add", "update", "delete", "noop"]],
                            "id": ["type": "STRING"],
                            "rule": [
                                "type": "OBJECT",
                                "properties": [
                                    "trigger": ["type": "STRING"],
                                    "action": ["type": "STRING"]
                                ] as [String: Any],
                                "required": ["trigger", "action"]
                            ] as [String: Any]
                        ] as [String: Any],
                        "required": ["op"]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "required": ["episodicAdds", "semanticUpdates", "proceduralUpdates"]
        ]
    }
}
