import Foundation

// MARK: - Companion Message

struct CompanionMessage: Codable, Identifiable {
    let id: String
    let role: CompanionRole
    let content: String
    let timestamp: Date

    init(role: CompanionRole, content: String) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum CompanionRole: String, Codable {
    case system
    case user
    case assistant
}

// MARK: - Companion Provider Protocol

/// LLM-agnostic interface for conversation and extraction.
/// Gemini today, OpenAI/Claude/Ollama tomorrow — only the adapter changes.
protocol CompanionProvider {
    /// Generate a natural conversational response.
    func generateResponse(
        messages: [CompanionMessage],
        systemPrompt: String,
        temperature: Double
    ) async throws -> String

    /// Extract structured health data from conversation. Returns raw JSON string.
    func extractHealthData(
        conversationText: String,
        extractionPrompt: String
    ) async throws -> String
}

// MARK: - Errors

enum CompanionError: Error, LocalizedError {
    case providerUnavailable
    case emptyResponse
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Companion provider is not available"
        case .emptyResponse:
            return "Received empty response from companion"
        case .extractionFailed(let detail):
            return "Health data extraction failed: \(detail)"
        }
    }
}
