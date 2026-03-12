import Foundation

/// Wraps GeminiService to conform to CompanionProvider.
/// This is the only file that knows about Gemini.
final class GeminiCompanionAdapter: CompanionProvider {

    private let geminiService: GeminiService

    init(geminiService: GeminiService = GeminiService()) {
        self.geminiService = geminiService
    }

    func generateResponse(
        messages: [CompanionMessage],
        systemPrompt: String,
        temperature: Double
    ) async throws -> String {
        // Flatten messages into a single prompt for Gemini's single-turn API.
        // System prompt is sent separately via system_instruction.
        let conversationText = flattenMessages(messages)
        let fullPrompt = "\(systemPrompt)\n\n\(conversationText)"

        let response = try await geminiService.sendTextRequest(text: fullPrompt)
        guard !response.isEmpty else {
            throw CompanionError.emptyResponse
        }
        return response
    }

    func extractHealthData(
        conversationText: String,
        extractionPrompt: String
    ) async throws -> String {
        let fullPrompt = "\(extractionPrompt)\n\n---\nConversation:\n\(conversationText)\n---\n\nReturn ONLY valid JSON."

        let response = try await geminiService.sendTextRequest(text: fullPrompt)
        guard !response.isEmpty else {
            throw CompanionError.extractionFailed("Empty response from extraction")
        }
        return cleanJSONResponse(response)
    }

    // MARK: - Private

    /// Flattens CompanionMessage array into a readable conversation string.
    private func flattenMessages(_ messages: [CompanionMessage]) -> String {
        messages
            .filter { $0.role != .system }
            .map { msg in
                let role = msg.role == .user ? "User" : "Assistant"
                return "\(role): \(msg.content)"
            }
            .joined(separator: "\n")
    }

    /// Strips markdown code fences if the LLM wraps JSON in them.
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
