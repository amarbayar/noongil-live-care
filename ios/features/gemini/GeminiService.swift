import Foundation
import UIKit

/// REST API client for Google Gemini (text, vision, and function calling).
class GeminiService {
    private let session = URLSession.shared
    private var systemPrompt = PromptService.companionSystemPrompt

    /// Update the system prompt with language-specific instructions.
    /// When Mongolian is selected in Local mode, instructs Gemini to respond in Mongolian.
    func updateLanguage(_ language: Language) {
        let basePrompt = PromptService.companionSystemPrompt
        switch language {
        case .mongolian:
            systemPrompt = basePrompt + "\n\nЧУХАЛ: Хэрэглэгч монгол хэлээр ярьж байна. Та ЗААВАЛ монгол хэлээр (кирилл бичгээр) хариулах ёстой. Хэзээ ч англи хэлээр хариулж болохгүй."
        case .english:
            systemPrompt = basePrompt
        }
    }

    /// Structured response from Gemini — either text or a function call.
    enum GeminiResponse {
        case text(String)
        case functionCall(name: String, args: [String: Any])
    }

    init() {}

    // MARK: - Smart Request (with function calling)

    /// Send a request to Gemini with tool declarations.
    /// Gemini may respond with text or call a function (e.g. "look" to use the camera).
    func sendSmartRequest(text: String) async throws -> GeminiResponse {
        let url = buildURL()
        let body = buildSmartBody(text: text)
        return try await sendRequestAndParse(url: url, body: body)
    }

    // MARK: - Vision Request

    /// Send a multimodal request with text and image to Gemini.
    func sendVisionRequest(text: String, image: UIImage) async throws -> String {
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            throw GeminiError.imageEncodingFailed
        }

        let base64Image = jpegData.base64EncodedString()
        let url = buildURL()
        let body = buildVisionBody(text: text, base64Image: base64Image)

        let response = try await sendRequestAndParse(url: url, body: body)
        switch response {
        case .text(let text):
            return text
        case .functionCall:
            // Shouldn't happen in vision request, but handle gracefully
            throw GeminiError.parseError
        }
    }

    // MARK: - Structured Output Request

    /// Send a request with JSON schema constraint. Gemini returns valid JSON matching the schema.
    /// Used for health data extraction where we need deterministic, typed output.
    func sendStructuredRequest(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) async throws -> [String: Any] {
        let url = buildURL()
        let body = buildStructuredBody(text: text, systemInstruction: systemInstruction, jsonSchema: jsonSchema)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse the structured JSON from Gemini's text response
        let geminiResponse = try parseFullResponse(data: data)
        switch geminiResponse {
        case .text(let jsonText):
            guard let jsonData = jsonText.data(using: .utf8),
                  let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw GeminiError.parseError
            }
            return dict
        case .functionCall:
            throw GeminiError.parseError
        }
    }

    // MARK: - Text-Only Request (no tools, for backward compat)

    /// Send a text-only request to Gemini without function calling.
    func sendTextRequest(text: String) async throws -> String {
        let url = buildURL()
        let body = buildTextBody(text: text)

        let response = try await sendRequestAndParse(url: url, body: body)
        switch response {
        case .text(let text):
            return text
        case .functionCall:
            throw GeminiError.parseError
        }
    }

    // MARK: - Private — URL

    private func buildURL() -> URL {
        let urlString = "\(Config.geminiBaseURL)/models/\(Config.geminiModel):generateContent?key=\(Config.geminiAPIKey)"
        return URL(string: urlString)!
    }

    // MARK: - Private — Tool Declarations

    private var toolDeclarations: [[String: Any]] {
        [
            [
                "functionDeclarations": [
                    [
                        "name": "look",
                        "description": "Look through the smart glasses camera to see what the user is seeing. Use this whenever the user asks you to look at something, describe what they see, identify objects, read text, take a picture, or any request that requires visual information from their perspective.",
                        "parameters": [
                            "type": "OBJECT",
                            "properties": [String: Any]()
                        ] as [String: Any]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Private — Body Builders

    private func buildSmartBody(text: String) -> [String: Any] {
        return [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": text]
                    ]
                ]
            ],
            "tools": toolDeclarations,
            "generationConfig": [
                "maxOutputTokens": 1024,
                "temperature": 0.7
            ]
        ]
    }

    private func buildTextBody(text: String) -> [String: Any] {
        return [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": text]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024,
                "temperature": 0.7
            ]
        ]
    }

    private func buildStructuredBody(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) -> [String: Any] {
        return [
            "system_instruction": [
                "parts": [["text": systemInstruction]]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": text]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.1,
                "responseMimeType": "application/json",
                "responseSchema": jsonSchema
            ]
        ]
    }

    private func buildVisionBody(text: String, base64Image: String) -> [String: Any] {
        let prompt = "\(systemPrompt)\n\nUser asked: \(text)\n\nDescribe what you see and answer the user's question."
        return [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024,
                "temperature": 0.7
            ]
        ]
    }

    // MARK: - Private — Network + Parsing

    private func sendRequestAndParse(url: URL, body: [String: Any]) async throws -> GeminiResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return try parseFullResponse(data: data)
    }

    /// Parse Gemini response, handling both text and function call responses.
    private func parseFullResponse(data: Data) throws -> GeminiResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first else {
            throw GeminiError.parseError
        }

        // Check for function call
        if let functionCall = firstPart["functionCall"] as? [String: Any],
           let name = functionCall["name"] as? String {
            let args = functionCall["args"] as? [String: Any] ?? [:]
            print("[GeminiService] Function call: \(name)(\(args))")
            return .functionCall(name: name, args: args)
        }

        // Check for text response
        if let text = firstPart["text"] as? String {
            return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        throw GeminiError.parseError
    }

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        case imageEncodingFailed
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                return "Failed to encode camera frame as JPEG"
            case .invalidResponse:
                return "Invalid response from Gemini API"
            case .apiError(let code, let message):
                return "Gemini API error (\(code)): \(message)"
            case .parseError:
                return "Failed to parse Gemini response"
            }
        }
    }
}
