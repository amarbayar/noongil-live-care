import UIKit

/// Calls Gemini API directly for image/video generation (API key auth).
/// Music generation goes through the backend (Lyria-002 requires Vertex AI OAuth).
final class GenerationService {
    private let apiKey = Config.geminiAPIKey
    private let baseURL = Config.geminiBaseURL
    private let session: URLSession
    private let backendClient: BackendClient
    private let authTokenProvider: (() async throws -> String?)?
    private let videoPollIntervalNanoseconds: UInt64
    private let videoMaxAttempts: Int

    init(
        backendClient: BackendClient = BackendClient(),
        authTokenProvider: (() async throws -> String?)? = nil,
        session: URLSession = .shared,
        videoPollIntervalNanoseconds: UInt64 = 10_000_000_000,
        videoMaxAttempts: Int = 36
    ) {
        self.session = session
        self.backendClient = backendClient
        self.authTokenProvider = authTokenProvider
        self.videoPollIntervalNanoseconds = videoPollIntervalNanoseconds
        self.videoMaxAttempts = videoMaxAttempts
    }

    // MARK: - Image (Imagen 4 via :predict endpoint)

    func generateImage(
        prompt: String,
        aspectRatio: String? = nil,
        onProgress: ((CreativeGenerationProgress) -> Void)? = nil
    ) async throws -> UIImage {
        let url = URL(string: "\(baseURL)/models/\(Config.geminiImageModel):predict")!
        onProgress?(
            CreativeGenerationProgress(
                stage: .starting,
                message: "I am sketching out your image now."
            )
        )

        var parameters: [String: Any] = ["sampleCount": 1]
        if let ar = aspectRatio {
            parameters["aspectRatio"] = ar
        }

        let body: [String: Any] = [
            "instances": [["prompt": prompt]],
            "parameters": parameters
        ]

        print("[GenerationService] Image request: model=\(Config.geminiImageModel), prompt=\(prompt.prefix(80))")
        let data = try await geminiRequest(url: url, body: body)
        onProgress?(
            CreativeGenerationProgress(
                stage: .finalizing,
                message: "I am finishing the image now."
            )
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            print("[GenerationService] Invalid JSON response: \(raw.prefix(500))")
            throw GenerationError.invalidImageData
        }

        // Imagen 4 :predict response: { "predictions": [{ "bytesBase64Encoded": "...", "mimeType": "..." }] }
        if let predictions = json["predictions"] as? [[String: Any]] {
            for prediction in predictions {
                if let base64 = prediction["bytesBase64Encoded"] as? String,
                   let imageData = Data(base64Encoded: base64),
                   let image = UIImage(data: imageData) {
                    print("[GenerationService] Image generated successfully (\(imageData.count) bytes)")
                    return image
                }
            }
        }

        // Check for error response
        if let error = json["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "unknown"
            throw GenerationError.apiError("Image API: \(msg)")
        }

        print("[GenerationService] Unexpected response: \(json.keys)")
        throw GenerationError.invalidImageData
    }

    // MARK: - Image with Reference (Gemini Flash — inline image + text → new image)

    func generateImageWithReference(
        prompt: String,
        referenceImage: UIImage,
        aspectRatio: String? = nil,
        onProgress: ((CreativeGenerationProgress) -> Void)? = nil
    ) async throws -> UIImage {
        let url = URL(string: "\(baseURL)/models/\(Config.geminiImageEditModel):generateContent?key=\(apiKey)")!
        onProgress?(
            CreativeGenerationProgress(
                stage: .starting,
                message: "I am reimagining your photo now."
            )
        )

        guard let jpegData = referenceImage.jpegData(compressionQuality: 0.85) else {
            throw GenerationError.invalidImageData
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": [
                        "mime_type": "image/jpeg",
                        "data": jpegData.base64EncodedString()
                    ]]
                ]
            ]],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"]
            ]
        ]

        print("[GenerationService] Image-edit request: model=\(Config.geminiImageEditModel), prompt=\(prompt.prefix(80))")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.apiError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GenerationError.apiError("Image edit API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        onProgress?(
            CreativeGenerationProgress(
                stage: .finalizing,
                message: "I am finishing the image now."
            )
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GenerationError.invalidImageData
        }

        for part in parts {
            // REST API returns camelCase: inlineData, mimeType
            let inlineData = (part["inlineData"] as? [String: Any])
                ?? (part["inline_data"] as? [String: Any])
            if let inlineData,
               let base64 = inlineData["data"] as? String,
               let imageData = Data(base64Encoded: base64),
               let image = UIImage(data: imageData) {
                print("[GenerationService] Image-edit generated successfully (\(imageData.count) bytes)")
                return image
            }
        }

        let responsePreview = String(data: data, encoding: .utf8)?.prefix(500) ?? "(binary)"
        print("[GenerationService] Image-edit: no image found in response parts. Response: \(responsePreview)")
        throw GenerationError.invalidImageData
    }

    // MARK: - Video (Gemini API direct, async polling)

    func generateVideo(
        prompt: String,
        aspectRatio: String? = nil,
        durationSeconds: Int? = nil,
        startingImage: UIImage? = nil,
        onProgress: ((CreativeGenerationProgress) -> Void)? = nil
    ) async throws -> URL {
        let url = URL(string: "\(baseURL)/models/veo-3.1-generate-preview:predictLongRunning")!
        onProgress?(
            CreativeGenerationProgress(
                stage: .starting,
                message: "I am getting your video started."
            )
        )

        var instance: [String: Any] = ["prompt": prompt]
        if let img = startingImage, let jpegData = img.jpegData(compressionQuality: 0.9) {
            instance["image"] = [
                "bytesBase64Encoded": jpegData.base64EncodedString(),
                "mimeType": "image/jpeg"
            ]
        }

        var params: [String: Any] = ["aspectRatio": aspectRatio ?? "16:9"]
        if let dur = durationSeconds { params["durationSeconds"] = dur }

        let body: [String: Any] = [
            "instances": [instance],
            "parameters": params
        ]

        let data = try await geminiRequest(url: url, body: body)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operationName = json["name"] as? String else {
            throw GenerationError.apiError("Failed to start video generation")
        }

        onProgress?(
            CreativeGenerationProgress(
                stage: .queued,
                message: "Your video is in line. I will keep checking on it.",
                fraction: 0.05
            )
        )

        // Poll for completion
        let pollURL = URL(string: "\(baseURL)/\(operationName)")!
        var transientPollFailureCount = 0
        for attempt in 1...videoMaxAttempts {
            try await Task.sleep(nanoseconds: videoPollIntervalNanoseconds)

            var pollRequest = URLRequest(url: pollURL)
            pollRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            pollRequest.timeoutInterval = 30

            let progressFraction = min(0.9, Double(attempt) / Double(max(videoMaxAttempts, 1)))
            onProgress?(
                CreativeGenerationProgress(
                    stage: .polling,
                    message: videoPollingMessage(for: attempt, maxAttempts: videoMaxAttempts),
                    fraction: progressFraction
                )
            )

            let statusData: Data
            do {
                let response = try await session.data(for: pollRequest)
                statusData = response.0
                transientPollFailureCount = 0
            } catch {
                transientPollFailureCount += 1
                onProgress?(
                    CreativeGenerationProgress(
                        stage: .retrying,
                        message: "I lost touch for a moment, so I am checking again.",
                        fraction: progressFraction
                    )
                )
                if transientPollFailureCount >= 3 {
                    throw error
                }
                continue
            }
            guard let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any] else {
                continue
            }

            if let error = status["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GenerationError.apiError(message)
            }

            if status["done"] as? Bool == true {
                if let response = status["response"] as? [String: Any],
                   let genResponse = response["generateVideoResponse"] as? [String: Any],
                   let samples = genResponse["generatedSamples"] as? [[String: Any]],
                   let video = samples.first?["video"] as? [String: Any],
                   let uri = video["uri"] as? String {
                    onProgress?(
                        CreativeGenerationProgress(
                            stage: .downloading,
                            message: "The video is ready. I am bringing it into the app now.",
                            fraction: 1.0
                        )
                    )
                    return try await downloadToTemp(uri: uri, apiKeyHeader: true, ext: "mp4")
                }
                throw GenerationError.apiError("Video completed but no URI returned")
            }

            if attempt == videoMaxAttempts {
                throw GenerationError.timeout
            }
        }

        throw GenerationError.timeout
    }

    // MARK: - Music (Backend proxy — Lyria-002 requires Vertex AI OAuth)

    struct MusicRequest: Encodable {
        let prompt: String
        let negativePrompt: String?
    }

    struct MusicResponse: Decodable {
        let audioBase64: String
        let mimeType: String
    }

    func generateMusic(
        prompt: String,
        negativePrompt: String? = nil,
        onProgress: ((CreativeGenerationProgress) -> Void)? = nil
    ) async throws -> Data {
        onProgress?(
            CreativeGenerationProgress(
                stage: .starting,
                message: "I am shaping the music now."
            )
        )
        if let authTokenProvider {
            backendClient.authToken = try await authTokenProvider()
        }

        let body = MusicRequest(prompt: prompt, negativePrompt: negativePrompt)
        let response: MusicResponse = try await backendClient.postAndDecode(
            "/api/generate/music", body: body, timeout: 60
        )
        onProgress?(
            CreativeGenerationProgress(
                stage: .finalizing,
                message: "I am loading the music into the app now.",
                fraction: 1.0
            )
        )

        guard let data = Data(base64Encoded: response.audioBase64) else {
            throw GenerationError.invalidAudioData
        }

        return data
    }

    // MARK: - Private

    private func geminiRequest(url: URL, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.apiError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GenerationError.apiError("API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        return data
    }

    private func downloadToTemp(uri: String, apiKeyHeader: Bool = false, ext: String) async throws -> URL {
        guard let url = URL(string: uri) else {
            throw GenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        if apiKeyHeader {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }

        let (data, _) = try await session.data(for: request)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: tempURL)
        return tempURL
    }

    private func videoPollingMessage(for attempt: Int, maxAttempts: Int) -> String {
        let ratio = Double(attempt) / Double(max(maxAttempts, 1))
        switch ratio {
        case ..<0.25:
            return "I am checking on your video now."
        case ..<0.65:
            return "Your video is still rendering. I will keep checking every few seconds."
        default:
            return "This is taking longer than usual, but I am still checking on it."
        }
    }

    enum GenerationError: Error, LocalizedError, Equatable {
        case invalidImageData
        case invalidAudioData
        case invalidURL
        case timeout
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .invalidImageData: return "Failed to decode image data"
            case .invalidAudioData: return "Failed to decode audio data"
            case .invalidURL: return "Invalid download URL"
            case .timeout: return "Generation timed out"
            case .apiError(let msg): return "Generation error: \(msg)"
            }
        }
    }
}
