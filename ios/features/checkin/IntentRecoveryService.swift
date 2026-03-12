import Foundation

/// Detects garbled ASR output and recovers user intent via LLM.
/// Works alongside CheckInService to handle dysarthric speech.
final class IntentRecoveryService {

    // MARK: - Dependencies

    private let provider: CompanionProvider
    private let confidenceThreshold: Float

    // MARK: - Init

    init(provider: CompanionProvider, confidenceThreshold: Float = 0.6) {
        self.provider = provider
        self.confidenceThreshold = confidenceThreshold
    }

    // MARK: - Detection

    /// Heuristic: should we attempt intent recovery on this ASR output?
    /// Uses text length relative to audio duration as a proxy for confidence.
    func shouldAttemptRecovery(text: String, audioDurationSeconds: Float) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or whitespace-only — definitely need recovery
        if trimmed.isEmpty { return true }

        // Very short text from long audio — likely garbled
        let wordCount = trimmed.split(separator: " ").count
        let wordsPerSecond = Float(wordCount) / max(audioDurationSeconds, 0.1)

        // Normal speech is ~2-3 words/second. Below 0.5 words/second
        // with at least 1.5s of audio suggests garbled output.
        if audioDurationSeconds >= 1.5 && wordsPerSecond < 0.5 {
            return true
        }

        return false
    }

    // MARK: - Recovery

    /// Sends garbled text through the LLM with context for intent interpretation.
    func recoverIntent(
        garbledText: String,
        conversationContext: String,
        accommodationLevel: SpeechAccommodationLevel
    ) async throws -> String {
        let severityDescription: String
        switch accommodationLevel {
        case .none: severityDescription = "no speech impairment"
        case .mild: severityDescription = "mild speech impairment (occasional unclear words)"
        case .moderate: severityDescription = "moderate speech impairment (frequently unclear speech)"
        case .severe: severityDescription = "severe speech impairment (most words are difficult to understand)"
        }

        let systemMessage = CompanionMessage(
            role: .system,
            content: """
            You are interpreting speech from a user with \(severityDescription). \
            The speech recognition system produced garbled or partial output. \
            Given the conversation context, interpret their most likely intent. \
            Return ONLY the interpreted meaning as a clear, natural sentence. \
            Do not add explanation or qualifiers.
            """
        )

        let userMessage = CompanionMessage(
            role: .user,
            content: """
            Conversation context: \(conversationContext)

            ASR output (possibly garbled): "\(garbledText)"

            What did the user most likely mean?
            """
        )

        let response = try await provider.generateResponse(
            messages: [systemMessage, userMessage],
            systemPrompt: systemMessage.content,
            temperature: 0.3
        )

        print("[IntentRecoveryService] Recovered '\(garbledText)' → '\(response)'")
        return response
    }

    /// Generates a confirmation prompt for the recovered intent.
    static func confirmationPrompt(recoveredText: String) -> String {
        "I think you said: \(recoveredText). Is that right?"
    }
}
