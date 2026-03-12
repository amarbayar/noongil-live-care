import Foundation
import UIKit

protocol CreativeGenerating {
    func generateImage(
        prompt: String,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage
    func generateImageWithReference(
        prompt: String,
        referenceImage: UIImage,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage
    func generateVideo(
        prompt: String,
        aspectRatio: String?,
        durationSeconds: Int?,
        startingImage: UIImage?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> URL
    func generateMusic(
        prompt: String,
        negativePrompt: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> Data
}

extension GenerationService: CreativeGenerating {}

/// Manages the creative refinement loop during Gemini Live sessions.
/// Mirrors the LiveCheckInManager pattern — system prompt tells Gemini to call
/// `get_creative_guidance` before every response; guidance returns round number,
/// brief state, and action (ask/confirm/generate).
@MainActor
final class CreativeFlowManager {
    typealias CanvasUpdateHandler = @MainActor (CreativeCanvasState?) -> Void
    typealias StatusAnnouncementHandler = @MainActor (String) -> Void

    // MARK: - State

    enum FlowState: String {
        case idle, gathering, clarifying, confirming, generating, presenting
    }

    private(set) var flowState: FlowState = .idle
    private var brief: CreativeBrief?
    private var transcript: [(role: String, text: String)] = []
    private var hasConfirmed = false
    private(set) var result: CreativeResult?
    private(set) var canvasState: CreativeCanvasState?
    var onCanvasStateChanged: CanvasUpdateHandler?
    var onStatusAnnouncementRequested: StatusAnnouncementHandler?

    private var generationTask: Task<Void, Never>?
    private var activeGenerationToken: UUID?
    private var pendingReadyAnnouncement = false
    private var lastGenerationFailureMessage: String?

    private let generationService: CreativeGenerating
    private let artifactLibrary: CreativeArtifactLibrarying
    private let composeMedia: (URL, Data) async throws -> URL

    private let minRounds = 3
    private let maxRounds = 5

    var hasInteractiveCanvasContext: Bool {
        generationTask != nil || canvasState != nil || flowState != .idle
    }

    // MARK: - Tool Declarations

    static let creativeToolDeclarations: [[String: Any]] = [
        [
            "name": "get_creative_guidance",
            "description": "Get guidance for the creative refinement conversation. Call this BEFORE every response to understand what has been clarified, what to ask next, and whether to generate. Always call this during a creative session.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ],
        [
            "name": "generate_image",
            "description": "Generate an image using the refined prompt. Only call when guidance action is 'generate'. Set referenceImage to 'canvas' to use the current photo on screen as a starting point.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "prompt": [
                        "type": "STRING",
                        "description": "The refined image generation prompt"
                    ] as [String: Any],
                    "aspectRatio": [
                        "type": "STRING",
                        "description": "Aspect ratio (e.g. '1:1', '16:9', '9:16')"
                    ] as [String: Any],
                    "referenceImage": [
                        "type": "STRING",
                        "description": "Set to 'canvas' to use the current photo on canvas as a reference image for generation."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["prompt"]
            ] as [String: Any]
        ],
        [
            "name": "generate_video",
            "description": "Generate a video using the refined prompt. Only call when guidance action is 'generate'.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "prompt": [
                        "type": "STRING",
                        "description": "The refined video generation prompt"
                    ] as [String: Any],
                    "aspectRatio": [
                        "type": "STRING",
                        "description": "Aspect ratio (e.g. '16:9', '9:16')"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["prompt"]
            ] as [String: Any]
        ],
        [
            "name": "generate_music",
            "description": "Generate music using the refined prompt. Only call when guidance action is 'generate'. NEVER include artist names, song titles, or band names — describe mood, style, tempo, and instruments instead.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "prompt": [
                        "type": "STRING",
                        "description": "The refined music generation prompt"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["prompt"]
            ] as [String: Any]
        ],
        [
            "name": "cancel_generation",
            "description": "Cancel the current image, video, or music generation when the person asks you to stop waiting or change their mind.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ],
        [
            "name": "close_canvas",
            "description": "Hide the current image, video, or music canvas without ending the voice session.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ],
        [
            "name": "show_canvas",
            "description": "Show the current hidden image, video, or music canvas again.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "mediaType": [
                        "type": "STRING",
                        "description": "Optional requested media type to reopen, such as image, video, music, or animation."
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "media_control",
            "description": "Control the current image, video, or music. Use for transport (play, pause, replay, seek, stop, volume, mute, speed, loop), image transforms (rotate, zoom), navigation (next, previous), lifecycle (delete, save), and display (fullscreen).",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "action": [
                        "type": "STRING",
                        "description": "The action: play, pause, replay, seek_forward, seek_backward, stop, volume_up, volume_down, mute, speed, loop, rotate_left, rotate_right, zoom_in, zoom_out, zoom_reset, next, previous, delete, save, fullscreen, exit_fullscreen."
                    ] as [String: Any],
                    "value": [
                        "type": "NUMBER",
                        "description": "Optional numeric value. For speed: playback rate (0.5, 1.0, 1.5, 2.0)."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["action"]
            ] as [String: Any]
        ],
        [
            "name": "recall_artifact",
            "description": "Search for a previously generated image, video, or music by description. Use when the person asks to find, recall, or show something they made before.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "description": [
                        "type": "STRING",
                        "description": "Natural language description of the artifact to search for"
                    ] as [String: Any],
                    "mediaType": [
                        "type": "STRING",
                        "description": "Optional filter: image, video, or music"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["description"]
            ] as [String: Any]
        ],
        [
            "name": "show_artifact",
            "description": "Display a specific artifact by its ID, returned from recall_artifact.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "artifactId": [
                        "type": "STRING",
                        "description": "The artifact ID to display"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["artifactId"]
            ] as [String: Any]
        ],
        [
            "name": "steer_music",
            "description": "Steer the currently streaming music by updating prompts or config. Use when the person asks to change the mood, tempo, instruments, or style of streaming music.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "prompts": [
                        "type": "ARRAY",
                        "description": "Weighted text prompts to steer the music. Each has 'text' and 'weight' (0.1-2.0).",
                        "items": [
                            "type": "OBJECT",
                            "properties": [
                                "text": ["type": "STRING", "description": "Musical description"] as [String: Any],
                                "weight": ["type": "NUMBER", "description": "Influence weight (default 1.0)"] as [String: Any]
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    "bpm": [
                        "type": "INTEGER",
                        "description": "Beats per minute (60-200)"
                    ] as [String: Any],
                    "brightness": [
                        "type": "NUMBER",
                        "description": "Tonal brightness (0.0-1.0)"
                    ] as [String: Any],
                    "density": [
                        "type": "NUMBER",
                        "description": "Note density (0.0-1.0)"
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["prompts"]
            ] as [String: Any]
        ],
    ]

    init(
        generationService: CreativeGenerating = GenerationService(),
        artifactLibrary: CreativeArtifactLibrarying = CreativeArtifactLibraryService(),
        composeMedia: @escaping (URL, Data) async throws -> URL = { videoURL, audioData in
            try await MediaComposer.compose(videoURL: videoURL, audioData: audioData)
        }
    ) {
        self.generationService = generationService
        self.artifactLibrary = artifactLibrary
        self.composeMedia = composeMedia
    }

    // MARK: - Start

    /// Initializes the creative flow and returns the system prompt for Gemini Live.
    func start(mediaType: CreativeMediaType) -> String {
        brief = CreativeBrief(mediaType: mediaType)
        flowState = .gathering
        transcript = []
        hasConfirmed = false
        result = nil
        canvasState = nil
        generationTask = nil
        activeGenerationToken = nil
        pendingReadyAnnouncement = false
        publishCanvasState()

        let basePrompt = PromptService.creativeSystemPrompt
        let context = """
        [Media type: \(mediaType.rawValue)]
        [Aspects to clarify: \(CreativeAspect.aspects(for: mediaType).map { $0.rawValue }.joined(separator: ", "))]
        """

        let prompt = basePrompt.replacingOccurrences(of: "{CONTEXT}", with: context)
        print("[CreativeFlowManager] Started creative flow (type=\(mediaType.rawValue))")
        return prompt
    }

    // MARK: - Transcript

    func addUserTranscript(_ text: String) {
        guard flowState != .idle, !text.isEmpty else { return }
        transcript.append((role: "user", text: text))
    }

    func addAssistantTranscript(_ text: String) {
        guard flowState != .idle, !text.isEmpty else { return }
        transcript.append((role: "assistant", text: text))
    }

    func setMediaType(_ mediaType: CreativeMediaType) {
        if brief == nil {
            brief = CreativeBrief(mediaType: mediaType)
        } else {
            brief?.mediaType = mediaType
        }
    }

    // MARK: - Guidance

    func handleGetCreativeGuidance(latestUserText: String? = nil) -> [String: Any] {
        // Fallback heuristics only.
        // Primary production path:
        // latest utterance -> extraction.creativeCanvasAction/mediaType ->
        // VoicePipeline -> guidanceForCanvasAction(...) -> deterministic tool call.
        if let latestUserText, shouldCloseCanvasFallback(for: latestUserText) {
            return makeCanvasGuidance(
                action: "chat",
                instruction: "They want to hide what's on screen. Call close_canvas, then let them know it's tucked away and you can bring it back anytime."
            )
        }

        if let latestUserText, shouldShowCanvasFallback(for: latestUserText) {
            let requestedMediaType = fallbackRequestedMediaType(in: latestUserText)
            let mediaTypeInstruction = requestedMediaType.map {
                " Pass mediaType '\($0.rawValue)' if you can."
            } ?? ""
            return makeCanvasGuidance(
                action: "chat",
                instruction: "They want to see the current or recent creation again. Call show_canvas, then let them know it's back on screen.\(mediaTypeInstruction)"
            )
        }

        if generationTask != nil {
            if let latestUserText, shouldCancelGenerationFallback(for: latestUserText) {
                return makeCanvasGuidance(
                    action: "chat",
                    instruction: "They want to stop waiting. Call cancel_generation, then reassure them it has been stopped."
                )
            }

            return makeCanvasGuidance(
                action: "chat",
                instruction: inFlightInstruction(for: latestUserText),
                generationStatus: "running"
            )
        }

        if pendingReadyAnnouncement, let canvasState, canvasState.status == .ready {
            pendingReadyAnnouncement = false
            return makeCanvasGuidance(
                action: "chat",
                instruction: "Let them know their \(canvasState.mediaType.rawValue) is ready and it is showing on screen now.",
                generationStatus: "ready"
            )
        }

        guard var brief = brief else {
            return ["error": "No active creative session"]
        }

        brief.round += 1
        self.brief = brief

        let action: String
        if brief.round > maxRounds {
            action = "generate"
            flowState = .generating
        } else if brief.round >= minRounds && brief.allClarified {
            if hasConfirmed {
                action = "generate"
                flowState = .generating
            } else {
                action = "confirm"
                flowState = .confirming
                hasConfirmed = true
            }
        } else if brief.round >= minRounds && brief.unclarifiedAspects.count <= 1 {
            if hasConfirmed {
                action = "generate"
                flowState = .generating
            } else {
                action = "confirm"
                flowState = .confirming
                hasConfirmed = true
            }
        } else {
            action = "ask"
            flowState = .clarifying
        }

        let nextAspect = brief.unclarifiedAspects.first?.rawValue ?? ""

        let instruction: String
        switch action {
        case "ask":
            instruction = "Reflect back what you've heard so far, then ask ONE creative question about '\(nextAspect)'. Use sensory language. Offer 2-3 vivid options if they seem unsure."
        case "confirm":
            instruction = "Read back the full creative brief in vivid, sensory language. Ask if they'd like to change anything or if they're ready to create."
        case "generate":
            instruction = "Tell them you're creating their \(brief.mediaType.rawValue) now. Be excited. Then IMMEDIATELY call generate_\(brief.mediaType == .music ? "music" : brief.mediaType == .video ? "video" : "image") with the refined prompt to actually generate it."
        default:
            instruction = "Continue the creative conversation."
        }

        let clarifiedDict = Dictionary(uniqueKeysWithValues:
            brief.clarifiedAspects.map { ($0.key.rawValue, $0.value) }
        )

        var guidance: [String: Any] = [
            "round": brief.round,
            "maxRounds": maxRounds,
            "mediaType": brief.mediaType.rawValue,
            "clarifiedAspects": clarifiedDict,
            "unclarifiedAspects": brief.unclarifiedAspects.map { $0.rawValue },
            "allClarified": brief.allClarified,
            "action": action,
            "instruction": instruction,
        ]

        if let canvasState {
            guidance["currentCanvas"] = canvasState.referenceSummary
            guidance["canvasVisible"] = canvasState.isVisible
        }

        print("[CreativeFlowManager] Guidance: round=\(brief.round), action=\(action), unclarified=\(brief.unclarifiedAspects.map { $0.rawValue })")
        return guidance
    }

    func guidanceForCanvasAction(
        _ action: String,
        preferredMediaType: CreativeMediaType? = nil
    ) -> [String: Any]? {
        switch action {
        case "show":
            let mediaTypeInstruction = preferredMediaType.map {
                " Pass mediaType '\($0.rawValue)' if you can."
            } ?? ""
            return makeCanvasGuidance(
                action: "chat",
                instruction: "They want to see a recent creation again. Call show_canvas, then let them know it is back on screen.\(mediaTypeInstruction)"
            )
        case "close":
            return makeCanvasGuidance(
                action: "chat",
                instruction: "They want to hide what is on screen. Call close_canvas, then let them know it is tucked away."
            )
        case "cancel":
            return makeCanvasGuidance(
                action: "chat",
                instruction: "They want to stop the current generation. Call cancel_generation, then reassure them it has been stopped."
            )
        case "status":
            return makeCanvasGuidance(
                action: "chat",
                instruction: inFlightInstruction(for: nil),
                generationStatus: generationTask == nil ? "idle" : "running"
            )
        default:
            return nil
        }
    }

    // MARK: - Generation Handlers

    func startImageGeneration(prompt: String, aspectRatio: String?, referenceImage: UIImage? = nil) -> [String: Any] {
        startGeneration(
            mediaType: .image,
            prompt: prompt,
            waitDescription: "Images usually take a short moment.",
            work: { [weak self] in
                guard let self else { return }
                _ = await self.handleGenerateImage(prompt: prompt, aspectRatio: aspectRatio, referenceImage: referenceImage)
            }
        )
    }

    func startVideoGeneration(prompt: String, aspectRatio: String?) -> [String: Any] {
        startGeneration(
            mediaType: .video,
            prompt: prompt,
            waitDescription: "Videos can take a little longer than pictures.",
            work: { [weak self] in
                guard let self else { return }
                _ = await self.handleGenerateVideo(prompt: prompt, aspectRatio: aspectRatio)
            }
        )
    }

    func startMusicGeneration(prompt: String) -> [String: Any] {
        startRealtimeMusic(prompt: prompt)
    }

    // MARK: - Realtime Music (Lyria)

    private var lyriaService: LyriaRealtimeService?
    private var streamingPlayer: StreamingMusicPlayer?

    func startRealtimeMusic(prompt: String) -> [String: Any] {
        if lyriaService != nil {
            return [
                "success": true,
                "status": "already_streaming",
                "instruction": "Tell them music is already streaming. They can steer it or ask to stop."
            ]
        }

        flowState = .generating

        let lyria = LyriaRealtimeService()
        let player = StreamingMusicPlayer()
        lyriaService = lyria
        streamingPlayer = player

        lyria.onAudioChunk = { [weak player] data in
            player?.enqueueChunk(data)
        }

        // Set callback once before connect — handles setup complete → prompts → play
        lyria.onConnectionStateChanged = { [weak self, weak lyria] state in
            Task { @MainActor [weak self] in
                self?.handleLyriaStateChange(state)
                if state == .ready {
                    print("[CreativeFlowManager] Lyria ready — sending prompts and play")
                    lyria?.setWeightedPrompts([
                        LyriaRealtimeService.WeightedPrompt(text: prompt, weight: 1.0)
                    ])
                    lyria?.play()
                }
            }
        }

        let artifactId = UUID().uuidString
        canvasState = CreativeCanvasState(
            artifactId: artifactId,
            mediaType: .music,
            prompt: prompt,
            status: .streaming,
            statusMessage: "Connecting to the music stream.",
            progressFraction: nil,
            progressDetail: "The music will start flowing in a moment.",
            result: nil,
            isVisible: true
        )
        publishCanvasState()

        lyria.connect()

        return [
            "success": true,
            "status": "started",
            "instruction": "Tell them you are starting the music stream now. It will begin playing in a moment. They can steer it by describing changes — like 'make it more chill' or 'add drums'."
        ]
    }

    func handleSteerMusic(
        prompts: [[String: Any]],
        bpm: Int? = nil,
        brightness: Double? = nil,
        density: Double? = nil
    ) -> [String: Any] {
        guard let lyria = lyriaService else {
            return ["success": false, "instruction": "Let them know there is no music streaming right now."]
        }

        let weightedPrompts = prompts.compactMap { dict -> LyriaRealtimeService.WeightedPrompt? in
            guard let text = dict["text"] as? String else { return nil }
            let weight = dict["weight"] as? Double ?? 1.0
            return LyriaRealtimeService.WeightedPrompt(text: text, weight: weight)
        }

        if !weightedPrompts.isEmpty {
            lyria.setWeightedPrompts(weightedPrompts)
        }

        if bpm != nil || brightness != nil || density != nil {
            var config = LyriaRealtimeService.MusicConfig()
            config.bpm = bpm
            config.brightness = brightness
            config.density = density
            lyria.setMusicConfig(config)
        }

        // Update canvas prompt to reflect steering
        if let firstPrompt = weightedPrompts.first {
            canvasState?.prompt = firstPrompt.text
            publishCanvasState()
        }

        return ["success": true, "instruction": "Briefly confirm the music is shifting to match their request."]
    }

    func stopRealtimeMusic() {
        lyriaService?.stop()
        lyriaService?.disconnect()
        lyriaService = nil
        streamingPlayer?.stop()
        streamingPlayer = nil
    }

    private func handleLyriaStateChange(_ state: LyriaRealtimeService.ConnectionState) {
        switch state {
        case .ready:
            canvasState?.status = .streaming
            canvasState?.statusMessage = "Music is streaming."
            canvasState?.progressDetail = "Tell me to change the mood, tempo, or instruments anytime."
            publishCanvasState()
        case .error(let msg):
            canvasState?.status = .failed
            canvasState?.statusMessage = "The music stream hit a snag: \(msg)"
            publishCanvasState()
            stopRealtimeMusic()
        case .disconnected:
            if canvasState?.status == .streaming {
                canvasState?.status = .cancelled
                canvasState?.statusMessage = "Music stream ended."
                publishCanvasState()
            }
        default:
            break
        }
    }

    func handleGenerateImage(prompt: String, aspectRatio: String?, referenceImage: UIImage? = nil) async -> [String: Any] {
        flowState = .generating

        do {
            let image: UIImage
            if let referenceImage {
                image = try await generationService.generateImageWithReference(
                    prompt: prompt,
                    referenceImage: referenceImage,
                    aspectRatio: aspectRatio,
                    onProgress: makeProgressHandler(for: .image)
                )
            } else {
                image = try await generationService.generateImage(
                    prompt: prompt,
                    aspectRatio: aspectRatio,
                    onProgress: makeProgressHandler(for: .image)
                )
            }

            updateResult(for: .image, prompt: prompt) { result in
                result.image = image
            }

            // For animation, don't present yet — wait for video and music
            if brief?.mediaType == .animation {
                return ["success": true, "status": "image_ready", "instruction": "Image generated. Now call generate_video with this image as starting point, using the same prompt adapted for video motion."]
            }

            flowState = .presenting
            print("[CreativeFlowManager] Image generated successfully")
            return ["success": true, "status": "complete", "instruction": "Tell them their image is ready and it's being shown on screen now."]
        } catch {
            print("[CreativeFlowManager] Image generation failed: \(error)")
            lastGenerationFailureMessage = friendlyFailureMessage(for: .image, error: error)
            flowState = .confirming
            hasConfirmed = false
            return ["success": false, "error": error.localizedDescription, "instruction": "Tell them there was a hiccup creating the image. Ask if they'd like to try again with a different description or adjust something. Do NOT start the clarification questions over. Just ask if they want to retry or change the prompt."]
        }
    }

    func handleGenerateVideo(prompt: String, aspectRatio: String?) async -> [String: Any] {
        flowState = .generating

        do {
            let videoURL = try await generationService.generateVideo(
                prompt: prompt,
                aspectRatio: aspectRatio,
                durationSeconds: nil,
                startingImage: result?.image,
                onProgress: makeProgressHandler(for: .video)
            )

            updateResult(for: .video, prompt: prompt) { result in
                result.videoURL = videoURL
            }

            // For animation, still need music
            if brief?.mediaType == .animation {
                return ["success": true, "status": "video_ready", "instruction": "Video generated. Now call generate_music to add a soundtrack."]
            }

            flowState = .presenting
            print("[CreativeFlowManager] Video generated successfully")
            return ["success": true, "status": "complete", "instruction": "Tell them their video is ready and it's playing on screen now."]
        } catch {
            print("[CreativeFlowManager] Video generation failed: \(error)")
            lastGenerationFailureMessage = friendlyFailureMessage(for: .video, error: error)
            flowState = .confirming
            hasConfirmed = false
            return ["success": false, "error": error.localizedDescription, "instruction": "Tell them there was a hiccup creating the video. Ask if they'd like to try again with a different description or adjust something. Do NOT start the clarification questions over. Just ask if they want to retry or change the prompt."]
        }
    }

    func handleGenerateMusic(prompt: String) async -> [String: Any] {
        flowState = .generating

        do {
            let audioData = try await generationService.generateMusic(
                prompt: prompt,
                negativePrompt: nil,
                onProgress: makeProgressHandler(for: .music)
            )

            updateResult(for: .music, prompt: prompt) { result in
                result.audioData = audioData
            }

            // For animation, compose video + audio
            if brief?.mediaType == .animation,
               let videoURL = result?.videoURL {
                do {
                    let composedURL = try await composeMedia(videoURL, audioData)
                    result?.composedVideoURL = composedURL
                    flowState = .presenting
                    print("[CreativeFlowManager] Animation composed successfully")
                    return ["success": true, "status": "complete", "instruction": "Tell them their animation with music is ready and it's playing on screen now."]
                } catch {
                    // Composition failed but video + audio are still available separately
                    flowState = .presenting
                    print("[CreativeFlowManager] Composition failed, presenting separate: \(error)")
                    return ["success": true, "status": "complete", "instruction": "Tell them the video and music are ready. The music will play alongside the video."]
                }
            }

            flowState = .presenting
            print("[CreativeFlowManager] Music generated successfully")
            return ["success": true, "status": "complete", "instruction": "Tell them their music is ready and it's playing now."]
        } catch {
            print("[CreativeFlowManager] Music generation failed: \(error)")
            lastGenerationFailureMessage = friendlyFailureMessage(for: .music, error: error)
            flowState = .confirming
            hasConfirmed = false
            return ["success": false, "error": error.localizedDescription, "instruction": "Tell them there was a hiccup creating the music. Ask if they'd like to try again with a different description or adjust something. Do NOT start the clarification questions over. Just ask if they want to retry or change the prompt."]
        }
    }

    // MARK: - Cancel

    func cancelGeneration() -> [String: Any] {
        // Handle streaming music cancel
        if lyriaService != nil {
            stopRealtimeMusic()
            if var canvasState {
                canvasState.status = .cancelled
                canvasState.statusMessage = "I stopped the music stream."
                canvasState.isVisible = false
                self.canvasState = canvasState
                publishCanvasState()
            }
            flowState = .idle
            return ["success": true, "status": "cancelled", "instruction": "Tell them you stopped the music stream and you can start something new whenever they're ready."]
        }

        guard generationTask != nil else {
            return ["success": false, "status": "nothing_to_cancel", "instruction": "Let them know there is nothing being created right now."]
        }

        generationTask?.cancel()
        generationTask = nil
        activeGenerationToken = nil
        flowState = result == nil ? .clarifying : .presenting

        if var canvasState {
            canvasState.status = .cancelled
            canvasState.statusMessage = "I stopped working on that."
            canvasState.progressFraction = nil
            canvasState.progressDetail = "We can start something new whenever you're ready."
            canvasState.isVisible = canvasState.result != nil
            self.canvasState = canvasState
            publishCanvasState()
        }

        return ["success": true, "status": "cancelled", "instruction": "Tell them you stopped the generation and you can try a new direction whenever they're ready."]
    }

    func closeCanvas() -> [String: Any] {
        // If streaming music, stop it entirely (can't "hide" a stream)
        if lyriaService != nil {
            stopRealtimeMusic()
        }

        guard var canvasState else {
            return ["success": false, "status": "no_canvas", "instruction": "Let them know there is nothing open on screen right now."]
        }
        canvasState.isVisible = false
        self.canvasState = canvasState
        publishCanvasState()
        return ["success": true, "status": "closed", "instruction": "Tell them it's tucked away, and you can bring it back anytime."]
    }

    func showCanvas(preferredMediaType: CreativeMediaType? = nil) -> [String: Any] {
        if var canvasState, canvasState.result != nil {
            canvasState.isVisible = true
            canvasState.playbackToken = UUID()
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": "visible", "instruction": "Tell them it is back on screen now."]
        }

        do {
            guard let restoredResult = try artifactLibrary.loadLatestArtifact(
                preferredMediaType: preferredMediaType
            ) else {
                return ["success": false, "status": "no_canvas", "instruction": "Let them know there is nothing saved on the canvas right now."]
            }

            pendingReadyAnnouncement = false
            let restoredCanvas = CreativeCanvasState(
                artifactId: UUID().uuidString,
                mediaType: restoredResult.mediaType,
                prompt: restoredResult.prompt,
                status: .ready,
                statusMessage: statusMessage(for: restoredResult.mediaType, isReady: true),
                progressFraction: 1.0,
                progressDetail: "I brought back the last saved \(restoredResult.resolvedMediaType.rawValue).",
                result: restoredResult,
                isVisible: true
            )
            self.canvasState = restoredCanvas
            result = restoredResult
            publishCanvasState()
            return ["success": true, "status": "visible", "instruction": "Tell them it is back on screen now."]
        } catch {
            print("[CreativeFlowManager] Failed to restore saved artifact: \(error)")
            return ["success": false, "status": "no_canvas", "instruction": "Let them know you could not reopen that saved creation right now."]
        }
    }

    // MARK: - Artifact Recall

    func searchArtifacts(query: String, mediaType: CreativeMediaType?) -> [String: Any] {
        do {
            let results = try artifactLibrary.searchArtifacts(query: query, mediaType: mediaType)
            if results.isEmpty {
                return [
                    "success": true,
                    "matches": [] as [[String: Any]],
                    "instruction": "Let them know you could not find any saved creations matching that description. Ask if they'd like to describe it differently."
                ]
            }
            let matches: [[String: Any]] = results.map { r in
                [
                    "artifactId": r.id,
                    "mediaType": r.mediaType.rawValue,
                    "prompt": r.prompt
                ]
            }
            return [
                "success": true,
                "matches": matches,
                "instruction": "Tell them what you found. Read back the prompt of the best match. If there are multiple, briefly list them. Then call show_artifact with the best match's artifactId to display it."
            ]
        } catch {
            return ["success": false, "error": error.localizedDescription, "instruction": "Let them know you had trouble searching saved creations."]
        }
    }

    func displayArtifact(by artifactId: String) -> [String: Any] {
        do {
            guard let loadedResult = try artifactLibrary.loadArtifact(by: artifactId) else {
                return ["success": false, "instruction": "Let them know you could not find that saved creation."]
            }

            result = loadedResult
            pendingReadyAnnouncement = false
            canvasState = CreativeCanvasState(
                artifactId: artifactId,
                mediaType: loadedResult.mediaType,
                prompt: loadedResult.prompt,
                status: .ready,
                statusMessage: "Here is your saved \(loadedResult.resolvedMediaType.rawValue).",
                progressFraction: 1.0,
                progressDetail: nil,
                result: loadedResult,
                isVisible: true
            )
            publishCanvasState()
            return ["success": true, "instruction": "Tell them their saved creation is back on screen now."]
        } catch {
            return ["success": false, "error": error.localizedDescription, "instruction": "Let them know you had trouble loading that creation."]
        }
    }

    func handleMediaControl(action: String, args: [String: Any] = [:]) -> [String: Any] {
        // Handle streaming music controls
        if canvasState?.status == .streaming, let lyria = lyriaService {
            switch action {
            case "pause":
                lyria.pause()
                streamingPlayer?.pause()
                return ["success": true, "status": "paused", "instruction": "Briefly confirm: Paused the music stream."]
            case "play":
                lyria.play()
                streamingPlayer?.play()
                return ["success": true, "status": "play", "instruction": "Briefly confirm: Resuming the music stream."]
            case "stop":
                stopRealtimeMusic()
                return closeCanvas()
            case "volume_up":
                streamingPlayer?.volume = min(1.0, (streamingPlayer?.volume ?? 0.8) + 0.2)
                return ["success": true, "status": "volume_up", "instruction": "Briefly confirm: Turning it up."]
            case "volume_down":
                streamingPlayer?.volume = max(0.0, (streamingPlayer?.volume ?? 0.8) - 0.2)
                return ["success": true, "status": "volume_down", "instruction": "Briefly confirm: Turning it down."]
            default:
                break
            }
        }

        guard var canvasState, canvasState.result != nil else {
            return ["success": false, "status": "no_media", "instruction": "Let them know there is nothing playing right now."]
        }

        // Actions handled directly via state (no player interaction needed)
        switch action {
        case "rotate_left":
            canvasState.imageRotationDegrees = (canvasState.imageRotationDegrees - 90).truncatingRemainder(dividingBy: 360)
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Rotated left."]
        case "rotate_right":
            canvasState.imageRotationDegrees = (canvasState.imageRotationDegrees + 90).truncatingRemainder(dividingBy: 360)
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Rotated right."]
        case "zoom_in":
            canvasState.imageZoomScale = min(3.0, canvasState.imageZoomScale + 1.0)
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Zoomed in."]
        case "zoom_out":
            canvasState.imageZoomScale = max(1.0, canvasState.imageZoomScale - 1.0)
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Zoomed out."]
        case "zoom_reset":
            canvasState.imageZoomScale = 1.0
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Zoom reset."]
        case "fullscreen":
            canvasState.isFullscreen = true
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Full screen."]
        case "exit_fullscreen":
            canvasState.isFullscreen = false
            self.canvasState = canvasState
            publishCanvasState()
            return ["success": true, "status": action, "instruction": "Briefly confirm: Back to normal."]
        case "next":
            return navigateArtifact(direction: .next)
        case "previous":
            return navigateArtifact(direction: .previous)
        case "delete":
            return deleteCurrentArtifact()
        default:
            break
        }

        // Parse MediaAction for player-interaction actions
        let mediaAction: CreativeCanvasState.MediaAction
        switch action {
        case "play": mediaAction = .play
        case "pause": mediaAction = .pause
        case "replay": mediaAction = .replay
        case "seek_forward": mediaAction = .seekForward
        case "seek_backward": mediaAction = .seekBackward
        case "stop": return closeCanvas()
        case "volume_up": mediaAction = .volumeUp
        case "volume_down": mediaAction = .volumeDown
        case "mute": mediaAction = .mute
        case "speed":
            let value = args["value"] as? Double ?? 1.0
            mediaAction = .speed(value)
        case "loop": mediaAction = .loop
        case "save": mediaAction = .save
        default:
            return ["success": false, "status": "unknown_action", "instruction": "Let them know you did not understand that playback command."]
        }

        canvasState.pendingMediaAction = mediaAction
        canvasState.mediaActionToken = UUID()
        if !canvasState.isVisible {
            canvasState.isVisible = true
        }
        self.canvasState = canvasState
        publishCanvasState()

        let confirmation: String
        switch mediaAction {
        case .play: confirmation = "Resuming playback."
        case .pause: confirmation = "Paused."
        case .replay: confirmation = "Playing from the beginning."
        case .seekForward: confirmation = "Skipping ahead."
        case .seekBackward: confirmation = "Rewinding a bit."
        case .stop: confirmation = "Stopped."
        case .volumeUp: confirmation = "Turning it up."
        case .volumeDown: confirmation = "Turning it down."
        case .mute: confirmation = "Toggling mute."
        case .speed(let v): confirmation = v == 1.0 ? "Normal speed." : "\(v)x speed."
        case .loop: confirmation = "Toggling loop."
        case .save: confirmation = "Saving to your photos."
        default: confirmation = "Done."
        }

        return ["success": true, "status": action, "instruction": "Briefly confirm: \(confirmation)"]
    }

    // MARK: - Artifact Navigation

    private enum NavigationDirection { case next, previous }

    private func navigateArtifact(direction: NavigationDirection) -> [String: Any] {
        do {
            let ids = try artifactLibrary.listArtifactIds()
            guard !ids.isEmpty else {
                return ["success": false, "status": "no_artifacts", "instruction": "Let them know there are no saved creations to navigate to."]
            }

            let currentId = canvasState?.artifactId
            let currentIndex = currentId.flatMap { id in ids.firstIndex(of: id) }

            let targetIndex: Int
            if let currentIndex {
                switch direction {
                case .next:
                    targetIndex = currentIndex + 1 < ids.count ? currentIndex + 1 : 0
                case .previous:
                    targetIndex = currentIndex - 1 >= 0 ? currentIndex - 1 : ids.count - 1
                }
            } else {
                targetIndex = 0
            }

            let targetId = ids[targetIndex]

            // Reset transforms before navigating
            canvasState?.imageRotationDegrees = 0
            canvasState?.imageZoomScale = 1.0

            let result = displayArtifact(by: targetId)
            return result
        } catch {
            return ["success": false, "error": error.localizedDescription, "instruction": "Let them know you had trouble navigating creations."]
        }
    }

    private func deleteCurrentArtifact() -> [String: Any] {
        guard let currentId = canvasState?.artifactId else {
            return ["success": false, "status": "no_media", "instruction": "Let them know there is nothing to delete."]
        }

        do {
            try artifactLibrary.deleteArtifact(id: currentId)

            // Try to navigate to next, or close if last
            let ids = try artifactLibrary.listArtifactIds()
            if let nextId = ids.first {
                canvasState?.imageRotationDegrees = 0
                canvasState?.imageZoomScale = 1.0
                _ = displayArtifact(by: nextId)
                return ["success": true, "status": "deleted", "instruction": "Briefly confirm: Deleted. Showing the next one."]
            } else {
                _ = closeCanvas()
                result = nil
                canvasState = nil
                publishCanvasState()
                return ["success": true, "status": "deleted_last", "instruction": "Briefly confirm: Deleted. That was the last one."]
            }
        } catch {
            return ["success": false, "error": error.localizedDescription, "instruction": "Let them know you had trouble deleting that creation."]
        }
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationToken = nil
        stopRealtimeMusic()
        flowState = .idle
        brief = nil
        transcript = []
        result = nil
        canvasState = nil
        hasConfirmed = false
        pendingReadyAnnouncement = false
        publishCanvasState()
        print("[CreativeFlowManager] Creative flow cancelled")
    }

    func waitForCurrentGeneration() async {
        await generationTask?.value
    }

    private func updateResult(
        for generatedType: CreativeMediaType,
        prompt: String,
        update: (inout CreativeResult) -> Void
    ) {
        let resolvedType = resolveMediaType(for: generatedType)
        if var existing = result {
            existing.mediaType = resolvedType
            existing.prompt = prompt
            // Clear stale media from previous generation type (except animation which accumulates)
            if brief?.mediaType != .animation {
                switch generatedType {
                case .image:
                    existing.videoURL = nil
                    existing.audioData = nil
                    existing.composedVideoURL = nil
                case .video:
                    existing.image = nil
                    existing.audioData = nil
                    existing.composedVideoURL = nil
                case .music:
                    existing.image = nil
                    existing.videoURL = nil
                    existing.composedVideoURL = nil
                case .animation:
                    break
                }
            }
            update(&existing)
            result = existing
            return
        }

        var created = CreativeResult(mediaType: resolvedType, prompt: prompt)
        update(&created)
        result = created
    }

    private func resolveMediaType(for generatedType: CreativeMediaType) -> CreativeMediaType {
        if brief?.mediaType == .animation {
            return .animation
        }
        brief?.mediaType = generatedType
        return generatedType
    }

    private func startGeneration(
        mediaType: CreativeMediaType,
        prompt: String,
        waitDescription: String,
        work: @escaping @MainActor () async -> Void
    ) -> [String: Any] {
        if generationTask != nil {
            return [
                "success": true,
                "status": "already_running",
                "instruction": "Tell them you're still working on the current \(canvasState?.mediaType.rawValue ?? mediaType.rawValue). Invite them to keep chatting or ask you to stop."
            ]
        }

        let artifactId = UUID().uuidString
        let token = UUID()
        activeGenerationToken = token
        flowState = .generating
        pendingReadyAnnouncement = false
        lastGenerationFailureMessage = nil

        canvasState = CreativeCanvasState(
            artifactId: artifactId,
            mediaType: mediaType,
            prompt: prompt,
            status: .generating,
            statusMessage: statusMessage(for: mediaType, isReady: false),
            progressFraction: 0.05,
            progressDetail: "I will keep you posted while this runs.",
            result: result,
            isVisible: true
        )
        publishCanvasState()

        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await work()
            guard self.activeGenerationToken == token else { return }

            self.generationTask = nil
            self.activeGenerationToken = nil

            if let result = self.result, self.lastGenerationFailureMessage == nil {
                let persistedResult = self.persistResultIfPossible(
                    artifactId: artifactId,
                    result: result
                )
                self.result = persistedResult
                let readyMessage = self.statusMessage(for: persistedResult.mediaType, isReady: true)
                if let onStatusAnnouncementRequested = self.onStatusAnnouncementRequested {
                    onStatusAnnouncementRequested(readyMessage)
                } else {
                    self.pendingReadyAnnouncement = true
                }
                self.canvasState = CreativeCanvasState(
                    artifactId: artifactId,
                    mediaType: persistedResult.mediaType,
                    prompt: persistedResult.prompt,
                    status: .ready,
                    statusMessage: readyMessage,
                    progressFraction: 1.0,
                    progressDetail: "It is on screen now.",
                    result: persistedResult,
                    isVisible: true
                )
            } else if var canvasState = self.canvasState {
                let failureMessage = self.lastGenerationFailureMessage ?? "I couldn't finish that one."
                canvasState.status = .failed
                canvasState.statusMessage = failureMessage
                canvasState.progressFraction = nil
                canvasState.progressDetail = "We can try again or change the idea."
                self.canvasState = canvasState

                // Announce failure verbally so Gemini can tell the user
                if let onStatusAnnouncementRequested = self.onStatusAnnouncementRequested {
                    onStatusAnnouncementRequested(failureMessage)
                }
            }

            self.publishCanvasState()
        }

        return [
            "success": true,
            "status": "started",
            "instruction": "Tell them you're creating it now. Mention that \(waitDescription) Ask them to be patient, and let them know they can keep chatting or ask you to stop while you work."
        ]
    }

    private func makeCanvasGuidance(
        action: String,
        instruction: String,
        generationStatus: String? = nil
    ) -> [String: Any] {
        var guidance: [String: Any] = [
            "action": action,
            "instruction": instruction,
        ]

        if let generationStatus {
            guidance["generationStatus"] = generationStatus
        }
        if let canvasState {
            guidance["currentCanvas"] = canvasState.referenceSummary
            guidance["canvasVisible"] = canvasState.isVisible
        }

        return guidance
    }

    /// Inject a captured photo into the creative canvas for display and further generation.
    func injectCapturedImage(_ image: UIImage, prompt: String) {
        result = CreativeResult(mediaType: .image, image: image, prompt: prompt)
        canvasState = CreativeCanvasState(
            artifactId: UUID().uuidString,
            mediaType: .image,
            prompt: prompt,
            status: .ready,
            statusMessage: "Photo ready",
            result: result,
            isVisible: true
        )
        publishCanvasState()
    }

    private func publishCanvasState() {
        onCanvasStateChanged?(canvasState)
    }

    private func makeProgressHandler(for mediaType: CreativeMediaType) -> (CreativeGenerationProgress) -> Void {
        { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.applyProgressUpdate(progress, mediaType: mediaType)
            }
        }
    }

    private func applyProgressUpdate(
        _ progress: CreativeGenerationProgress,
        mediaType: CreativeMediaType
    ) {
        guard var canvasState else { return }
        guard canvasState.status == .generating else { return }

        canvasState.mediaType = mediaType
        canvasState.statusMessage = progress.message
        canvasState.progressFraction = progress.fraction
        canvasState.progressDetail = progressDetail(for: progress.stage)
        self.canvasState = canvasState
        publishCanvasState()
    }

    private func progressDetail(for stage: CreativeGenerationProgress.Stage) -> String? {
        switch stage {
        case .starting:
            return "I just kicked it off."
        case .queued:
            return "You can keep chatting while I wait on it."
        case .polling:
            return "I am checking again in the background."
        case .downloading:
            return "It is coming into the app now."
        case .finalizing:
            return "I am getting it ready to show."
        case .retrying:
            return "I hit a bump and I am trying again."
        }
    }

    private func persistResultIfPossible(
        artifactId: String,
        result: CreativeResult
    ) -> CreativeResult {
        do {
            return try artifactLibrary.saveArtifact(artifactId: artifactId, result: result)
        } catch {
            print("[CreativeFlowManager] Failed to persist creative artifact: \(error)")
            return result
        }
    }

    private func inFlightInstruction(for latestUserText: String?) -> String {
        let status = canvasState?.statusMessage ?? "I'm still working on it."
        if isStatusQuestionFallback(latestUserText) {
            return "Tell them you're still working on it. Then explain that \(status.lowercased()) They can keep talking while you work, or ask you to stop."
        }
        return "Briefly mention that you're still working on it and that \(status.lowercased()) Then answer their latest question naturally. Remind them they can keep chatting while you work."
    }

    private func statusMessage(for mediaType: CreativeMediaType, isReady: Bool) -> String {
        if isReady {
            switch mediaType {
            case .image:
                return "Your image is ready and showing on screen."
            case .video:
                return "Your video is ready and showing on screen."
            case .music:
                return "Your music is ready and playing on screen."
            case .animation:
                return "Your animation is ready and showing on screen."
            }
        }

        switch mediaType {
        case .image:
            return "I'm drawing it now. This should only take a short moment."
        case .video:
            return "I'm animating it now. Videos can take a little longer."
        case .music:
            return "I'm composing it now. Give me a little while to shape the sound."
        case .animation:
            return "I'm building the animation now. This can take a bit longer."
        }
    }

    private func shouldCancelGenerationFallback(for text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = ["cancel", "stop that", "never mind", "nevermind", "forget it", "don't do that"]
        return phrases.contains(where: { lower.contains($0) })
    }

    private func shouldCloseCanvasFallback(for text: String) -> Bool {
        guard canvasState?.result != nil else { return false }
        let lower = text.lowercased()
        let phrases = ["close the image", "close the video", "close that", "hide that", "put that away", "close it"]
        return phrases.contains(where: { lower.contains($0) })
    }

    private func shouldShowCanvasFallback(for text: String) -> Bool {
        let lower = text.lowercased()
        return (lower.contains("show") || lower.contains("open") || lower.contains("back"))
            && (lower.contains("again") || lower.contains("canvas"))
    }

    private func isStatusQuestionFallback(_ text: String?) -> Bool {
        guard let text else { return false }
        let lower = text.lowercased()
        let phrases = ["is it ready", "how long", "still working", "done yet", "status", "what's happening", "where is it"]
        return phrases.contains(where: { lower.contains($0) })
    }

    private func fallbackRequestedMediaType(in text: String) -> CreativeMediaType? {
        let lower = text.lowercased()
        if lower.contains("animation") { return .animation }
        if lower.contains("video") { return .video }
        if lower.contains("music") || lower.contains("song") || lower.contains("audio") { return .music }
        if lower.contains("image") || lower.contains("picture") || lower.contains("photo") { return .image }
        return nil
    }

    private func friendlyFailureMessage(
        for mediaType: CreativeMediaType,
        error: Error
    ) -> String {
        if let generationError = error as? GenerationService.GenerationError {
            switch generationError {
            case .timeout:
                return "This \(mediaType.rawValue) took longer than expected, so I stopped waiting. We can try again whenever you want."
            case .apiError(let message) where message.localizedCaseInsensitiveContains("429"):
                return "Too many requests hit at once, so I need a short pause before trying again."
            case .apiError(let message) where message.localizedCaseInsensitiveContains("network"):
                return "My connection wobbled while making that \(mediaType.rawValue). Let's try again in a moment."
            case .apiError(let message) where isContentFilterError(message):
                return "The \(mediaType.rawValue) prompt was too specific or referenced something protected. Let's try describing it differently — maybe focus on the mood or style instead of specific names."
            default:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("internet") || description.contains("network") {
            return "My connection wobbled while making that \(mediaType.rawValue). Let's try again in a moment."
        }
        if isContentFilterError(description) {
            return "The \(mediaType.rawValue) prompt was too specific or referenced something protected. Let's try describing it differently — maybe focus on the mood or style instead of specific names."
        }
        return "I hit a snag while making that \(mediaType.rawValue), but we can try again or change the idea."
    }

    private func isContentFilterError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("recitation")
            || lower.contains("content filter")
            || lower.contains("blocked")
            || lower.contains("try modifying your prompt")
            || lower.contains("safety")
    }
}
