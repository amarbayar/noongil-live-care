import Foundation
import UIKit

/// Orchestrator for three pipeline modes:
/// - Local:    VAD → Enhance → ASR → Gemini REST → TTS → Audio playback
/// - Live:     Audio → Gemini Live WebSocket (native audio in/out) → Audio playback
/// - Live+TTS: Audio → Gemini Live WebSocket (text out) → On-device TTS → Audio playback
/// State machine: IDLE → LISTENING → PROCESSING → SPEAKING → IDLE
@MainActor
final class VoicePipeline: ObservableObject {
    enum PipelineState: String {
        case idle = "Idle"
        case listening = "Listening"
        case processing = "Processing"
        case speaking = "Speaking"
    }

    struct ConversationEntry: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        let timestamp = Date()

        enum Role {
            case user, assistant
        }
    }

    // MARK: - Published State

    @Published var state: PipelineState = .idle
    @Published var conversation: [ConversationEntry] = []
    @Published var isInitialized = false
    @Published var initError: String?
    @Published var isMicActive = false
    @Published var isSpeakerActive = false
    @Published var language: Language = .mongolian
    @Published var speakerId: Int = 0
    @Published var ttsSpeed: Float = 1.0
    @Published var enhancementMode: AudioEnhancementMode = .denoiseOnly

    // Pipeline mode
    @Published var pipelineMode: PipelineMode = .local
    @Published var liveVoiceId: String = "Puck"
    @Published var liveConnectionState: GeminiLiveService.ConnectionState = .disconnected

    // Speech accommodation for dysarthric users
    @Published var speechAccommodation: SpeechAccommodationLevel = .none

    // MARK: - Services

    let audioService = AudioService()
    private let vadService = VADService()
    private let asrService = ASRService()
    private let ttsService = TTSService()
    let geminiService = GeminiService()
    private let enhancerService = AudioEnhancerService()
    private let geminiLiveService = GeminiLiveService()

    /// Consent service — gates Live/Live+TTS on voice processing consent (BIPA).
    var consentService: ConsentService?

    /// Reference to camera service for capturing frames (set by the view layer)
    var cameraService: CameraService?

    /// Reference to phone camera service for photo capture + preview (set by the view layer)
    var phoneCameraService: PhoneCameraService?
    @Published var cameraPreviewActive = false

    /// When set and active, speech is routed through the check-in flow instead of Gemini.
    var checkInCoordinator: CheckInCoordinator?

    /// When set, speech is checked for report trigger keywords and routed through the report flow.
    var reportFlowCoordinator: ReportFlowCoordinator?

    /// Reference to voice message inbox service for tool call handling.
    var voiceMessageInboxService: VoiceMessageInboxService?

    /// Context string injected when the session starts from a voice message notification.
    var pendingVoiceMessageContext: String?

    /// Active Live check-in manager (only during Live mode check-ins).
    private var liveCheckInManager: LiveCheckInManager?

    /// Active creative flow manager (only during creative generation sessions).
    private var creativeFlowManager: CreativeFlowManager?
    @Published var creativeResult: CreativeResult?
    @Published var creativeCanvas: CreativeCanvasState?
    private var companionSessionRecorder: CompanionSessionProjectionRecorder?
    private var lastRecordedCreativeArtifactId: String?
    private var pendingCreativeStatusAnnouncement: String?

    /// Unified guidance service — replaces mode-switching with intent-aware guidance.
    private(set) var guidanceService: UnifiedGuidanceService?

    /// Cross-session memory service — loads/saves episodic, semantic, procedural memories.
    private(set) var memoryService: MemoryService?

    /// Whether the unified guidance flow is active (vs legacy mode-switching).
    private var unifiedGuidanceActive = false
    private var unifiedSessionCompletionTask: Task<Void, Never>?

    /// Tool declarations for voice message playback/dismissal.
    static let voiceMessageToolDeclarations: [[String: Any]] = [
        [
            "name": "play_voice_message",
            "description": "Play a caregiver's voice message through the canvas. Call when user agrees to listen.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "messageId": ["type": "STRING", "description": "ID of the voice message"]
                ],
                "required": ["messageId"]
            ]
        ],
        [
            "name": "dismiss_voice_message",
            "description": "Mark a voice message as listened/dismissed so the user won't be reminded again. Call when user declines to listen or asks to skip/delete.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "messageId": ["type": "STRING", "description": "ID of the voice message"]
                ],
                "required": ["messageId"]
            ]
        ]
    ]

    /// Extra tool declarations to merge into Gemini Live default tools.
    var defaultExtraTools: [[String: Any]] = []
    var creativeAuthTokenProvider: (() async throws -> String?)?

    private var isRunning = false
    /// When true, sends an empty turn after connection to prompt Gemini to greet first.
    var proactiveGreeting = false
    private var currentProcessingTask: Task<Void, Never>?

    // Test seams for transport completion without touching the real WebSocket.
    var toolResponseSender: ((String, [String: Any], @escaping () -> Void) -> Void)?
    var stopSessionOverride: (() -> Void)?

    /// Accumulates partial input transcription in live mode
    private var pendingUserTranscript: String = ""
    /// Accumulates partial output transcription in live mode
    private var pendingAssistantTranscript: String = ""
    /// Accumulates streamed model text in liveText mode (for TTS on turn complete)
    private var pendingModelText: String = ""
    /// Auto-capture timeout tasks (keyed by camera string for cancellation)
    private var cameraAutoCaptureTasks: [String: Task<Void, Never>] = [:]

    /// Single source of truth for whether the pipeline currently owns an active session.
    /// Home views are recreated across tab switches, so they must derive session state
    /// from the pipeline rather than local view state.
    var hasActiveSession: Bool {
        SessionActivity.isActive(
            isCapturingAudio: audioService.isCapturing,
            isSpeakerActive: isSpeakerActive,
            liveConnectionState: liveConnectionState
        )
    }

    // MARK: - Configuration

    /// Apply feature flag defaults to pipeline settings.
    func configure(with flags: FeatureFlagService) {
        if let mode = AudioEnhancementMode(rawValue: flags.enhancementModeDefault) {
            enhancementMode = mode
        }
        if let mode = PipelineMode(rawValue: flags.pipelineModeDefault) {
            pipelineMode = mode
        }
    }

    // MARK: - Initialization

    @Published var vadReady = false
    @Published var asrReady = false
    @Published var ttsReady = false
    @Published var denoiserReady = false

    /// Initialize all ML models (VAD, ASR, TTS). Call once before starting pipeline.
    /// Reports per-model status; pipeline is considered initialized when VAD + ASR are ready.
    func initializeModels() {
        var errors: [String] = []

        do {
            try vadService.initialize(accommodation: speechAccommodation)
            vadReady = true
        } catch {
            vadReady = false
            errors.append("VAD: \(error.localizedDescription)")
        }

        do {
            try asrService.initialize(language: language, accommodation: speechAccommodation)
            asrReady = true
        } catch {
            asrReady = false
            errors.append("ASR: \(error.localizedDescription)")
        }

        do {
            try ttsService.initialize(language: language)
            ttsReady = true
        } catch {
            ttsReady = false
            errors.append("TTS: \(error.localizedDescription)")
        }

        do {
            try enhancerService.initialize()
            denoiserReady = true
        } catch {
            denoiserReady = false
            errors.append("Denoiser: \(error.localizedDescription)")
        }

        if errors.isEmpty {
            isInitialized = true
            initError = nil
        } else {
            // Pipeline can work without TTS (will just show text), but needs VAD + ASR
            isInitialized = vadReady && asrReady
            initError = errors.joined(separator: "\n")
        }
    }

    /// Switch language and re-initialize ASR + TTS models.
    func switchLanguage(_ newLanguage: Language) {
        guard newLanguage != language else { return }
        let wasRunning = isRunning
        if wasRunning { stop() }

        language = newLanguage
        speakerId = 0
        isInitialized = false
        asrReady = false
        ttsReady = false
        initError = nil

        // Update Gemini REST prompt for Local mode
        geminiService.updateLanguage(newLanguage)

        initializeModels()

        if wasRunning, isInitialized {
            try? start()
        }
    }

    // MARK: - Pipeline Control

    /// Start the voice pipeline in the selected mode.
    func start() throws {
        // BIPA: Live/Live+TTS stream audio to Google — require voice processing consent.
        if pipelineMode == .live || pipelineMode == .liveText {
            guard consentService?.voiceProcessingConsent == true else {
                throw PipelineError.voiceConsentRequired
            }
        }

        switch pipelineMode {
        case .local:
            guard isInitialized else { throw PipelineError.notInitialized }
        case .liveText:
            guard ttsReady else { throw PipelineError.ttsNotReady }
        case .live:
            break // No local models needed
        }
        guard !isRunning else { return }

        // Configure audio session for the selected pipeline mode
        try audioService.configureAudioSession(for: pipelineMode)

        switch pipelineMode {
        case .local:
            startLocalMode()
        case .live:
            try startLiveMode(nativeAudio: true)
        case .liveText:
            try startLiveMode(nativeAudio: false)
        }
    }

    /// Stop the voice pipeline.
    func stop() {
        print("[VoicePipeline] stop() — isRunning=\(isRunning), checkInActive=\(checkInCoordinator?.isCheckInActive ?? false), unified=\(unifiedGuidanceActive)")

        let recorderToComplete = companionSessionRecorder
        companionSessionRecorder = nil

        // Save memories if unified session was active
        if unifiedGuidanceActive {
            if unifiedSessionCompletionTask == nil,
               let guidance = guidanceService,
               let memory = memoryService {
                let transcript = guidance.transcript
                if !transcript.isEmpty {
                    unifiedSessionCompletionTask = Task { @MainActor [weak self, guidance, memory, transcript] in
                        await self?.handleSessionComplete(
                            guidance: guidance,
                            memory: memory,
                            transcript: transcript
                        )
                    }
                }
            }
            guidanceService = nil
            memoryService = nil
            unifiedGuidanceActive = false
        }

        // Cancel any active Live check-in
        if liveCheckInManager?.isActive == true {
            liveCheckInManager?.cancel()
            liveCheckInManager = nil
        }
        checkInCoordinator?.isCheckInActive = false

        // Cancel any active creative flow
        if creativeFlowManager?.flowState != .idle {
            creativeFlowManager?.cancel()
            creativeFlowManager = nil
        }
        creativeCanvas = nil
        creativeResult = nil
        pendingCreativeStatusAnnouncement = nil

        isRunning = false
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        audioService.stopPlayback()
        audioService.stopCapture()

        switch pipelineMode {
        case .local:
            vadService.reset()
        case .live, .liveText:
            geminiLiveService.disconnect()
            liveConnectionState = .disconnected
            pendingUserTranscript = ""
            pendingAssistantTranscript = ""
            pendingModelText = ""
        }

        state = .idle
        isMicActive = false
        isSpeakerActive = false

        if let recorderToComplete {
            Task { @MainActor [weak self] in
                await recorderToComplete.completeSession()
                await self?.memoryProjectionService?.drainPendingMemoryProjections()
                recorderToComplete.reset()
            }
        }
    }

    // MARK: - Local Mode

    private func startLocalMode() {
        // Update Gemini system prompt with current language
        geminiService.updateLanguage(language)

        // Wire up VAD callbacks
        vadService.onSpeechStart = { [weak self] in
            Task { @MainActor in
                self?.state = .listening
            }
        }

        vadService.onSpeechEnd = { [weak self] in
            Task { @MainActor in
                _ = self // State transitions in handleSpeechSegment
            }
        }

        vadService.onSpeechSegment = { [weak self] samples in
            Task { @MainActor in
                self?.processSpeechSegment(samples)
            }
        }

        // Wire up audio capture → VAD (runs on audio thread)
        let vad = vadService
        audioService.onAudioChunk = { samples in
            vad.processAudio(samples)
        }

        do {
            try audioService.startCapture()
            isRunning = true
            isMicActive = true
            state = .idle
        } catch {
            print("[VoicePipeline] startCapture failed: \(error)")
        }
    }

    // MARK: - Live Mode (native audio) & Live+TTS Mode (text → on-device TTS)

    private func startLiveMode(nativeAudio: Bool) throws {
        let checkInPrepared = liveCheckInManager != nil
        let toolNames = geminiLiveService.extraFunctionDeclarations.compactMap { $0["name"] as? String }
        print("[VoicePipeline] startLiveMode(nativeAudio=\(nativeAudio), checkInPrepared=\(checkInPrepared), unified=\(unifiedGuidanceActive)) — tools=\(toolNames)")

        // Configure GeminiLiveService — skip if already configured by unified or check-in prep
        geminiLiveService.useNativeAudio = nativeAudio
        geminiLiveService.voiceName = liveVoiceId
        if !checkInPrepared && !unifiedGuidanceActive {
            geminiLiveService.systemInstruction = PromptService.companionSystemPrompt
            geminiLiveService.extraFunctionDeclarations = defaultExtraTools
        }

        // Wire up callbacks
        geminiLiveService.onConnectionStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.liveConnectionState = state
                switch state {
                case .ready:
                    self?.state = .listening
                    self?.flushPendingCreativeStatusAnnouncementIfPossible()
                    print("[VoicePipeline] Live: ready, listening (nativeAudio=\(nativeAudio))")
                    // Proactive greeting: send a text trigger so Gemini greets first
                    if self?.proactiveGreeting == true {
                        self?.proactiveGreeting = false
                        if let vmContext = self?.pendingVoiceMessageContext {
                            self?.geminiLiveService.sendText(vmContext)
                            self?.pendingVoiceMessageContext = nil
                            print("[VoicePipeline] Sent voice message proactive greeting")
                        } else {
                            self?.geminiLiveService.sendText("[check-in session started]")
                            print("[VoicePipeline] Sent proactive greeting trigger")
                        }
                    }
                case .error(let msg):
                    print("[VoicePipeline] Live error: \(msg)")
                default:
                    break
                }
            }
        }

        // Audio output — only used in native audio mode
        geminiLiveService.onAudioOutput = { [weak self] audioData in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                self.state = .speaking
                self.isSpeakerActive = true
                self.audioService.scheduleAudioChunk(
                    int16Data: audioData,
                    sampleRate: Config.geminiLiveOutputSampleRate
                )
            }
        }

        // Streamed model text — only used in liveText mode (accumulated for TTS)
        geminiLiveService.onModelText = { [weak self] text in
            Task { @MainActor in
                guard let self = self else { return }
                self.pendingModelText += text
                // Show streaming text in conversation as it arrives
                if let lastIdx = self.conversation.indices.last,
                   self.conversation[lastIdx].role == .assistant {
                    self.conversation[lastIdx].text = self.pendingModelText
                } else {
                    self.conversation.append(ConversationEntry(role: .assistant, text: self.pendingModelText))
                }
            }
        }

        // Input transcription (what the user said)
        geminiLiveService.onInputTranscript = { [weak self] text in
            Task { @MainActor in
                guard let self = self else { return }
                if self.pendingUserTranscript.isEmpty {
                    self.pendingUserTranscript = text
                    self.conversation.append(ConversationEntry(role: .user, text: text))
                } else {
                    self.pendingUserTranscript = text
                    if let lastIdx = self.conversation.indices.last,
                       self.conversation[lastIdx].role == .user {
                        self.conversation[lastIdx].text = text
                    }
                }
                self.liveCheckInManager?.upsertUserTranscript(text)
                self.guidanceService?.upsertUserTranscript(text)
            }
        }

        // Output transcription (transcript of native audio — only in audio mode)
        geminiLiveService.onOutputTranscript = { [weak self] text in
            Task { @MainActor in
                guard let self = self else { return }
                if self.pendingAssistantTranscript.isEmpty {
                    self.pendingAssistantTranscript = text
                    self.conversation.append(ConversationEntry(role: .assistant, text: text))
                } else {
                    self.pendingAssistantTranscript += text
                    if let lastIdx = self.conversation.indices.last,
                       self.conversation[lastIdx].role == .assistant {
                        self.conversation[lastIdx].text = self.pendingAssistantTranscript
                    }
                }
                self.liveCheckInManager?.upsertAssistantTranscript(self.pendingAssistantTranscript)
                self.guidanceService?.upsertAssistantTranscript(self.pendingAssistantTranscript)
            }
        }

        // Turn complete — also feed accumulated model text to Live check-in manager (liveText mode)
        geminiLiveService.onTurnComplete = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }

                if !nativeAudio && !self.pendingModelText.isEmpty {
                    self.liveCheckInManager?.upsertAssistantTranscript(self.pendingModelText)
                    self.guidanceService?.upsertAssistantTranscript(self.pendingModelText)
                    // Live+TTS mode: synthesize accumulated text with on-device TTS
                    self.state = .speaking
                    self.isSpeakerActive = true
                    let textToSpeak = self.pendingModelText

                    if let ttsAudio = self.ttsService.synthesize(
                        text: textToSpeak,
                        speakerId: self.speakerId,
                        speed: self.ttsSpeed
                    ) {
                        await withCheckedContinuation { continuation in
                            self.audioService.playTTSAudio(
                                samples: ttsAudio.samples,
                                sampleRate: ttsAudio.sampleRate
                            ) {
                                continuation.resume()
                            }
                        }
                    }
                }

                await self.liveCheckInManager?.finalizePendingTranscriptTurn()
                await self.guidanceService?.finalizePendingTranscriptTurn()
                await self.finalizeCompanionSessionTurnIfNeeded()

                self.state = .listening
                self.isSpeakerActive = false
                self.pendingUserTranscript = ""
                self.pendingAssistantTranscript = ""
                self.pendingModelText = ""
                self.flushPendingCreativeStatusAnnouncementIfPossible()
            }
        }

        // Interruption
        geminiLiveService.onInterrupted = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                self.audioService.stopPlayback()
                self.state = .listening
                self.isSpeakerActive = false
                self.pendingAssistantTranscript = ""
                self.pendingModelText = ""
                print("[VoicePipeline] Live: interrupted by user")
            }
        }

        // Tool calls (camera + check-in guidance)
        geminiLiveService.onToolCall = { [weak self] id, name, args in
            Task { @MainActor in
                guard let self = self else { return }
                print("[VoicePipeline] onToolCall: \(name) id=\(id)")
                if name == "look" {
                    // Try glasses camera first, fall back to phone back camera
                    if let frame = self.cameraService?.captureCurrentFrame(),
                       let jpegData = frame.jpegData(compressionQuality: 0.7) {
                        self.geminiLiveService.sendImage(jpegData)
                        self.geminiLiveService.sendToolResponse(
                            id: id,
                            response: ["result": "Image captured and sent from glasses."]
                        )
                    } else if let phoneCamera = self.phoneCameraService {
                        await phoneCamera.start(position: .back)
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if let jpegData = phoneCamera.captureCurrentFrameAsJPEG(quality: 0.7) {
                            self.geminiLiveService.sendImage(jpegData)
                            self.geminiLiveService.sendToolResponse(
                                id: id,
                                response: ["result": "Image captured and sent from phone camera."]
                            )
                        } else {
                            self.geminiLiveService.sendToolResponse(
                                id: id,
                                response: ["result": "Camera not available."]
                            )
                        }
                        phoneCamera.stop()
                    } else {
                        self.geminiLiveService.sendToolResponse(
                            id: id,
                            response: ["result": "Camera not available."]
                        )
                    }
                } else if name == "get_guidance" {
                    // Unified guidance path
                    if let guidance = self.guidanceService {
                        var result = await guidance.handleGetGuidance()

                        // When intent is creative, merge creative flow guidance
                        // so get_guidance manages the full creative lifecycle
                        let shouldUseCreativeGuidance =
                            guidance.shouldRouteThroughCreativeTools
                            || self.creativeFlowManager?.hasInteractiveCanvasContext == true
                        if shouldUseCreativeGuidance,
                           (result["action"] as? String) != "close" {
                            let manager = self.ensureCreativeFlowManager()
                            let creative: [String: Any]
                            if let canvasAction = guidance.latestCreativeCanvasAction,
                               let override = manager.guidanceForCanvasAction(
                                    canvasAction,
                                    preferredMediaType: guidance.latestCreativeRequestedMediaType
                               ) {
                                creative = override
                            } else {
                                creative = manager.handleGetCreativeGuidance(
                                    latestUserText: guidance.latestUserTranscriptText
                                )
                            }
                            // Override action/instruction with creative flow's round-aware guidance
                            result["action"] = creative["action"]
                            result["instruction"] = creative["instruction"]
                            if let round = creative["round"] {
                                result["round"] = round
                            }
                            if let maxRounds = creative["maxRounds"] {
                                result["maxRounds"] = maxRounds
                            }
                            if let clarifiedAspects = creative["clarifiedAspects"] {
                                result["clarifiedAspects"] = clarifiedAspects
                            }
                            if let unclarifiedAspects = creative["unclarifiedAspects"] {
                                result["unclarifiedAspects"] = unclarifiedAspects
                            }
                            if let mediaType = creative["mediaType"] {
                                result["mediaType"] = mediaType
                            }
                            if let generationStatus = creative["generationStatus"] {
                                result["generationStatus"] = generationStatus
                            }
                            if let currentCanvas = creative["currentCanvas"] {
                                result["currentCanvas"] = currentCanvas
                            }
                            if let canvasVisible = creative["canvasVisible"] {
                                result["canvasVisible"] = canvasVisible
                            }
                            print("[VoicePipeline] Creative guidance merged: action=\(creative["action"] ?? "nil"), round=\(creative["round"] ?? "nil")")
                        }

                        self.geminiLiveService.sendToolResponse(id: id, response: result)
                    } else {
                        self.geminiLiveService.sendToolResponse(
                            id: id,
                            response: ["error": "No guidance service"]
                        )
                    }
                } else if name == "complete_session" {
                    if let guidance = self.guidanceService,
                       let memory = self.memoryService {
                        await self.completeUnifiedSessionToolCall(
                            id: id,
                            guidance: guidance,
                            memory: memory
                        )
                    } else {
                        let coordinator = self.makeUnifiedSessionCompletionCoordinator()
                        await coordinator.finish(id: id) {}
                    }
                } else if name == "get_check_in_guidance" {
                    // Legacy check-in guidance path
                    if let manager = self.liveCheckInManager {
                        let guidance = await manager.handleGetGuidance()
                        self.geminiLiveService.sendToolResponse(id: id, response: guidance)
                    } else {
                        self.geminiLiveService.sendToolResponse(
                            id: id,
                            response: ["error": "No active check-in"]
                        )
                    }
                } else if name == "complete_check_in" {
                    // Legacy check-in complete path
                    if let manager = self.liveCheckInManager {
                        let result = await manager.handleComplete()
                        self.geminiLiveService.sendToolResponse(id: id, response: result)
                        self.endLiveCheckIn()
                    } else {
                        self.geminiLiveService.sendToolResponse(
                            id: id,
                            response: ["success": false, "error": "No active check-in"]
                        )
                    }
                } else if name == "get_creative_guidance" {
                    let manager = self.ensureCreativeFlowManager()
                    let guidance: [String: Any]
                    if let unifiedGuidance = self.guidanceService,
                       let canvasAction = unifiedGuidance.latestCreativeCanvasAction,
                       let override = manager.guidanceForCanvasAction(
                            canvasAction,
                            preferredMediaType: unifiedGuidance.latestCreativeRequestedMediaType
                       ) {
                        guidance = override
                    } else {
                        guidance = manager.handleGetCreativeGuidance(
                            latestUserText: self.guidanceService?.latestUserTranscriptText
                        )
                    }
                    self.geminiLiveService.sendToolResponse(id: id, response: guidance)
                } else if name == "generate_image" {
                    let manager = self.ensureCreativeFlowManager()
                    let argsDict = args as? [String: Any] ?? [:]
                    let prompt = argsDict["prompt"] as? String ?? ""
                    let aspect = argsDict["aspectRatio"] as? String
                    let refImageArg = argsDict["referenceImage"] as? String
                    let referenceImage: UIImage? = (refImageArg == "canvas") ? manager.result?.image : nil
                    manager.setMediaType(.image)
                    print("[VoicePipeline] generate_image called: prompt=\(prompt.prefix(80)), aspect=\(aspect ?? "nil"), ref=\(refImageArg ?? "nil")")
                    let result = manager.startImageGeneration(prompt: prompt, aspectRatio: aspect, referenceImage: referenceImage)
                    print("[VoicePipeline] generate_image result: \(result["success"] ?? "nil"), hasCreativeResult=\(self.creativeResult != nil)")
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "generate_video" {
                    let manager = self.ensureCreativeFlowManager()
                    let prompt = (args as? [String: Any])?["prompt"] as? String ?? ""
                    let aspect = (args as? [String: Any])?["aspectRatio"] as? String
                    manager.setMediaType(.video)
                    let result = manager.startVideoGeneration(prompt: prompt, aspectRatio: aspect)
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "generate_music" {
                    let manager = self.ensureCreativeFlowManager()
                    let prompt = (args as? [String: Any])?["prompt"] as? String ?? ""
                    manager.setMediaType(.music)
                    let result = manager.startMusicGeneration(prompt: prompt)
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "cancel_generation" {
                    let manager = self.ensureCreativeFlowManager()
                    let result = manager.cancelGeneration()
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "close_canvas" {
                    let manager = self.ensureCreativeFlowManager()
                    let result = manager.closeCanvas()
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "show_canvas" {
                    let manager = self.ensureCreativeFlowManager()
                    let preferredMediaType: CreativeMediaType?
                    if let mediaTypeRaw = (args as? [String: Any])?["mediaType"] as? String {
                        preferredMediaType = CreativeMediaType(rawValue: mediaTypeRaw)
                    } else {
                        preferredMediaType = nil
                    }
                    let result = manager.showCanvas(preferredMediaType: preferredMediaType)
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "media_control" {
                    let manager = self.ensureCreativeFlowManager()
                    let argsDict = args as? [String: Any] ?? [:]
                    let action = argsDict["action"] as? String ?? ""
                    let result = manager.handleMediaControl(action: action, args: argsDict)
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "steer_music" {
                    let manager = self.ensureCreativeFlowManager()
                    let argsDict = args as? [String: Any] ?? [:]
                    let prompts = argsDict["prompts"] as? [[String: Any]] ?? []
                    let bpm = argsDict["bpm"] as? Int
                    let brightness = argsDict["brightness"] as? Double
                    let density = argsDict["density"] as? Double
                    let result = manager.handleSteerMusic(
                        prompts: prompts, bpm: bpm, brightness: brightness, density: density
                    )
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "take_photo" {
                    let argsDict = args as? [String: Any] ?? [:]
                    let cameraStr = argsDict["camera"] as? String ?? "back"
                    let filterStr = argsDict["filter"] as? String
                    let position: PhoneCameraService.CameraPosition = cameraStr == "front" ? .front : .back

                    guard let phoneCamera = self.phoneCameraService else {
                        self.geminiLiveService.sendToolResponse(
                            id: id, response: ["error": "Phone camera not available."]
                        )
                        return
                    }

                    if let filter = filterStr {
                        phoneCamera.setFilter(filter)
                    }
                    await phoneCamera.start(position: position)
                    self.cameraPreviewActive = true

                    // Respond immediately — preview stays open for user to tap shutter
                    self.geminiLiveService.sendToolResponse(
                        id: id,
                        response: ["result": "Camera preview is now open with \(cameraStr) camera. The person can see the live feed and tap the shutter button to capture. The photo will be sent to you automatically."]
                    )

                    // Auto-capture after 10s if user hasn't tapped shutter
                    self.cameraAutoCaptureTasks[cameraStr] = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        guard let self, self.cameraPreviewActive else { return }
                        await self.captureAndSendPhoto(camera: position, cameraStr: cameraStr)
                    }
                } else if name == "apply_filter" {
                    let argsDict = args as? [String: Any] ?? [:]
                    let filterStr = argsDict["filter"] as? String ?? "none"

                    if let phoneCamera = self.phoneCameraService {
                        phoneCamera.setFilter(filterStr)
                        self.geminiLiveService.sendToolResponse(
                            id: id,
                            response: ["result": "Filter set to \(filterStr)."]
                        )
                    } else {
                        self.geminiLiveService.sendToolResponse(
                            id: id, response: ["error": "Phone camera not available."]
                        )
                    }
                } else if name == "recall_artifact" {
                    let manager = self.ensureCreativeFlowManager()
                    let argsDict = args as? [String: Any] ?? [:]
                    let query = argsDict["description"] as? String ?? ""
                    let mediaType: CreativeMediaType?
                    if let mediaTypeRaw = argsDict["mediaType"] as? String {
                        mediaType = CreativeMediaType(rawValue: mediaTypeRaw)
                    } else {
                        mediaType = nil
                    }
                    let result = manager.searchArtifacts(query: query, mediaType: mediaType)
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "show_artifact" {
                    let manager = self.ensureCreativeFlowManager()
                    let argsDict = args as? [String: Any] ?? [:]
                    let artifactId = argsDict["artifactId"] as? String ?? ""
                    let result = manager.displayArtifact(by: artifactId)
                    self.geminiLiveService.sendToolResponse(id: id, response: result)
                } else if name == "play_voice_message" {
                    let messageId = (args as? [String: Any])?["messageId"] as? String ?? ""
                    if let service = self.voiceMessageInboxService,
                       let message = service.messages.first(where: { $0.id == messageId }) {
                        self.playVoiceMessage(message)
                        Task { await service.markAsListened(message) }
                        self.geminiLiveService.sendToolResponse(id: id, response: [
                            "success": true, "status": "playing",
                            "instruction": "The voice message is now playing on screen. Wait for it to finish, then ask how they feel about it."
                        ])
                    } else {
                        self.geminiLiveService.sendToolResponse(id: id, response: [
                            "success": false, "error": "Message not found"
                        ])
                    }
                } else if name == "dismiss_voice_message" {
                    let messageId = (args as? [String: Any])?["messageId"] as? String ?? ""
                    if let service = self.voiceMessageInboxService,
                       let message = service.messages.first(where: { $0.id == messageId }) {
                        Task { await service.markAsListened(message) }
                        self.geminiLiveService.sendToolResponse(id: id, response: [
                            "success": true, "status": "dismissed",
                            "instruction": "The message has been dismissed. Move on naturally."
                        ])
                    } else {
                        self.geminiLiveService.sendToolResponse(id: id, response: [
                            "success": false, "error": "Message not found"
                        ])
                    }
                } else if name == "google_search" {
                    // Gemini Live may send google_search as a function call instead of handling server-side
                    print("[VoicePipeline] google_search tool call received — Live API bug, responding gracefully")
                    self.geminiLiveService.sendToolResponse(
                        id: id,
                        response: ["result": "Web search is temporarily unavailable. Please answer from your existing knowledge."]
                    )
                } else {
                    // Unknown tool — respond with error so Gemini doesn't hang
                    print("[VoicePipeline] Unknown tool call: \(name)")
                    self.geminiLiveService.sendToolResponse(
                        id: id,
                        response: ["error": "Unknown tool: \(name)"]
                    )
                }
            }
        }

        // Stream audio directly to Gemini Live
        let liveService = geminiLiveService
        var audioChunkCount = 0
        audioService.onAudioChunk = { samples in
            audioChunkCount += 1
            if audioChunkCount == 1 {
                print("[VoicePipeline] First audio chunk → Gemini (\(samples.count) samples)")
            } else if audioChunkCount % 500 == 0 {
                print("[VoicePipeline] Audio chunks: \(audioChunkCount), state=\(liveService.state)")
            }
            liveService.sendAudio(samples)
        }

        // Start audio capture
        try audioService.startCapture()
        isRunning = true
        isMicActive = true
        state = .idle

        // Connect to Gemini Live WebSocket
        geminiLiveService.connect()
    }

    // MARK: - Local Pipeline Processing

    /// Cancel any in-flight processing and start new segment.
    private func processSpeechSegment(_ samples: [Float]) {
        // Cancel previous processing if still running
        currentProcessingTask?.cancel()
        audioService.stopPlayback()

        currentProcessingTask = Task { [weak self] in
            await self?.handleSpeechSegment(samples)
        }
    }

    private func handleSpeechSegment(_ samples: [Float]) async {
        guard isRunning, !Task.isCancelled else { return }

        state = .processing

        // 1. Enhance the speech segment (SBR / Denoise / both)
        let enhancedSamples = enhancerService.enhance(samples: samples, mode: enhancementMode)

        // 2. Run ASR on the enhanced speech segment
        let transcript = asrService.recognize(samples: enhancedSamples)

        guard !transcript.isEmpty, !Task.isCancelled else {
            if isRunning { state = .idle }
            return
        }

        // Add user entry to conversation
        conversation.append(ConversationEntry(role: .user, text: transcript))
        await recordCompanionTurn(role: .user, text: transcript)

        // 3. Route through report flow, check-in coordinator, or Gemini
        let responseText: String
        if let reportCoord = reportFlowCoordinator, reportCoord.isActive {
            // Report flow active — route through coordinator
            switch reportCoord.flowState {
            case .awaitingPeriod:
                if let result = reportCoord.handlePeriodSelection(transcript) {
                    let summary = reportCoord.generateReport(
                        days: result.days,
                        checkIns: [],  // Populated by view layer via storage
                        medications: [],
                        userName: nil
                    )
                    responseText = result.response + " " + summary
                } else {
                    responseText = "I didn't catch the time period. You can say something like \"last two weeks\" or \"past month\"."
                }
            case .presenting:
                if let result = reportCoord.handlePresentationResponse(transcript) {
                    responseText = result.response
                } else {
                    responseText = "You can say \"share it\", \"read more\", or \"done\"."
                }
            default:
                responseText = "I'm still preparing the report. One moment."
            }
        } else if let reportCoord = reportFlowCoordinator, reportCoord.detectReportTrigger(transcript) {
            // New report trigger detected
            responseText = reportCoord.beginReportFlow()
        } else if checkInCoordinator?.isCheckInActive == true {
            // Check-in active — route through coordinator
            if let response = await checkInCoordinator?.handleUserSpeech(transcript) {
                responseText = response
            } else {
                if isRunning { state = .idle }
                return
            }
        } else {
            // Normal path — send to Gemini with function calling
            do {
                let geminiResponse = try await geminiService.sendSmartRequest(text: transcript)

                switch geminiResponse {
                case .text(let text):
                    responseText = text

                case .functionCall(let name, _):
                    if name == "look" {
                        if let frame = cameraService?.captureCurrentFrame() {
                            responseText = try await geminiService.sendVisionRequest(text: transcript, image: frame)
                        } else {
                            responseText = try await geminiService.sendTextRequest(
                                text: transcript + "\n[Camera unavailable — no frame available. Answer based on context only.]"
                            )
                        }
                    } else {
                        responseText = try await geminiService.sendTextRequest(text: transcript)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                let errorMsg = "Error: \(error.localizedDescription)"
                conversation.append(ConversationEntry(role: .assistant, text: errorMsg))
                if isRunning { state = .idle }
                return
            }
        }

        guard !responseText.isEmpty, isRunning, !Task.isCancelled else {
            if isRunning { state = .idle }
            return
        }

        // Add assistant entry to conversation
        conversation.append(ConversationEntry(role: .assistant, text: responseText))
        await recordCompanionTurn(role: .assistant, text: responseText)

        // 4. Run TTS on the response
        state = .speaking
        isSpeakerActive = true

        guard let ttsAudio = ttsService.synthesize(text: responseText, speakerId: speakerId, speed: ttsSpeed) else {
            if isRunning { state = .idle }
            isSpeakerActive = false
            return
        }

        guard !Task.isCancelled else {
            isSpeakerActive = false
            return
        }

        // 5. Play TTS audio through glasses speaker
        await withCheckedContinuation { continuation in
            audioService.playTTSAudio(
                samples: ttsAudio.samples,
                sampleRate: ttsAudio.sampleRate
            ) {
                continuation.resume()
            }
        }

        isSpeakerActive = false

        // 6. Return to idle
        if isRunning, !Task.isCancelled {
            state = .idle
        }
    }

    /// Clear conversation history.
    func clearConversation() {
        conversation.removeAll()
    }

    /// Speak arbitrary text through the TTS → audio pipeline.
    /// Adds the text to conversation as an assistant entry.
    func speakText(_ text: String) {
        guard !text.isEmpty, isRunning else { return }

        conversation.append(ConversationEntry(role: .assistant, text: text))
        Task { @MainActor [weak self] in
            await self?.recordCompanionTurn(role: .assistant, text: text)
        }

        currentProcessingTask?.cancel()
        currentProcessingTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }

            self.state = .speaking
            self.isSpeakerActive = true

            if let ttsAudio = self.ttsService.synthesize(text: text, speakerId: self.speakerId, speed: self.ttsSpeed) {
                await withCheckedContinuation { continuation in
                    self.audioService.playTTSAudio(
                        samples: ttsAudio.samples,
                        sampleRate: ttsAudio.sampleRate
                    ) {
                        continuation.resume()
                    }
                }
            }

            self.isSpeakerActive = false
            if self.isRunning, !Task.isCancelled {
                self.state = .idle
            }
        }
    }

    // MARK: - Live Check-In

    /// Storage and user ID for Live check-in creation. Set by the view layer.
    var storageService: StorageService?
    var graphSyncService: GraphSyncService?
    var memoryProjectionService: MemoryProjectionService?
    var userId: String?

    /// Start a check-in in Live mode using the function-call guidance loop.
    /// If called while the pipeline is already running, disconnects and reconnects
    /// with check-in tools (mid-session check-in start).
    func startLiveCheckIn(type: CheckInType = .adhoc) {
        print("[VoicePipeline] startLiveCheckIn() — mode=\(pipelineMode), isRunning=\(isRunning)")
        guard pipelineMode == .live || pipelineMode == .liveText else {
            print("[VoicePipeline] startLiveCheckIn requires Live or LiveText mode")
            return
        }
        guard isRunning else {
            print("[VoicePipeline] Pipeline not running")
            return
        }
        guard let userId = userId else {
            print("[VoicePipeline] No userId set for Live check-in")
            return
        }

        let manager = LiveCheckInManager(
            geminiService: geminiService,
            storageService: storageService,
            graphSyncService: graphSyncService,
            userId: userId
        )
        manager.onComplete = { [weak self] in
            // Will be called from handleComplete — endLiveCheckIn handles the rest
        }
        liveCheckInManager = manager

        Task {
            do {
                print("[VoicePipeline] Live check-in: calling manager.start()...")
                let systemPrompt = try await manager.start(type: type)
                print("[VoicePipeline] Live check-in: manager.start() done, disconnecting...")

                // Disconnect, reconfigure, reconnect with check-in prompt + tools
                geminiLiveService.disconnect()
                print("[VoicePipeline] Live check-in: reconnecting with check-in tools...")
                geminiLiveService.systemInstruction = systemPrompt
                geminiLiveService.extraFunctionDeclarations = LiveCheckInManager.checkInToolDeclarations
                geminiLiveService.connect()

                checkInCoordinator?.isCheckInActive = true
                print("[VoicePipeline] Live check-in started successfully")
            } catch {
                print("[VoicePipeline] Failed to start Live check-in: \(error)")
                liveCheckInManager = nil
            }
        }
    }

    /// Prepare check-in context and configure Gemini Live with check-in tools BEFORE
    /// connecting. Call this before start() when a check-in is due to avoid a wasteful
    /// double WebSocket connection (connect → disconnect → reconnect).
    func prepareLiveCheckIn(type: CheckInType = .adhoc) async -> Bool {
        guard pipelineMode == .live || pipelineMode == .liveText else { return false }
        guard let userId = userId else { return false }

        let manager = LiveCheckInManager(
            geminiService: geminiService,
            storageService: storageService,
            graphSyncService: graphSyncService,
            userId: userId
        )
        manager.onComplete = { [weak self] in
            // Will be called from handleComplete — endLiveCheckIn handles the rest
        }

        do {
            print("[VoicePipeline] prepareLiveCheckIn: loading context...")
            let systemPrompt = try await manager.start(type: type)

            // Pre-configure Gemini Live with check-in tools so the first connect()
            // in startLiveMode goes directly to check-in mode.
            geminiLiveService.systemInstruction = systemPrompt
            geminiLiveService.extraFunctionDeclarations = LiveCheckInManager.checkInToolDeclarations

            liveCheckInManager = manager
            checkInCoordinator?.isCheckInActive = true
            print("[VoicePipeline] prepareLiveCheckIn: ready (single-connection path)")
            return true
        } catch {
            print("[VoicePipeline] prepareLiveCheckIn failed: \(error)")
            return false
        }
    }

    /// End the Live check-in and return to normal conversation mode.
    private func endLiveCheckIn() {
        checkInCoordinator?.isCheckInActive = false
        liveCheckInManager = nil

        // Disconnect, reset to normal prompt + tools, reconnect
        geminiLiveService.disconnect()
        geminiLiveService.systemInstruction = PromptService.companionSystemPrompt
        geminiLiveService.extraFunctionDeclarations = defaultExtraTools
        geminiLiveService.connect()

        print("[VoicePipeline] Live check-in ended, returning to normal conversation")
    }

    // MARK: - Creative Flow

    /// Lazily creates a CreativeFlowManager when a creative tool call arrives.
    private func ensureCreativeFlowManager() -> CreativeFlowManager {
        if let existing = creativeFlowManager, existing.flowState != .idle {
            return existing
        }
        let manager = CreativeFlowManager(
            generationService: GenerationService(authTokenProvider: creativeAuthTokenProvider)
        )
        manager.onCanvasStateChanged = { [weak self] canvasState in
            guard let self else { return }
            self.creativeCanvas = canvasState
            self.creativeResult = canvasState?.result

            guard let canvasState,
                  canvasState.status == .ready,
                  self.lastRecordedCreativeArtifactId != canvasState.artifactId else {
                return
            }

            HapticService.generationComplete()
            self.lastRecordedCreativeArtifactId = canvasState.artifactId
            Task { @MainActor [weak self] in
                await self?.recordCreativeArtifactIfNeeded(from: canvasState.result)
            }
        }
        manager.onStatusAnnouncementRequested = { [weak self] message in
            self?.queueCreativeStatusAnnouncement(message)
        }
        _ = manager.start(mediaType: .image) // default to image; type refined by which generate_* is called
        creativeFlowManager = manager
        print("[VoicePipeline] Created CreativeFlowManager")
        return manager
    }

    // MARK: - Unified Guidance Session

    /// Prepare the unified guidance session: load memories, build prompt, configure tools.
    /// Call this before start() when unified_guidance_enabled flag is on.
    func prepareUnifiedSession(companionName: String = "Mira") async -> Bool {
        guard pipelineMode == .live || pipelineMode == .liveText else { return false }
        guard let userId = userId else { return false }

        // Wait for any pending memory save from the previous session before loading
        if let pendingTask = unifiedSessionCompletionTask {
            print("[VoicePipeline] Waiting for previous session memory save...")
            await pendingTask.value
            unifiedSessionCompletionTask = nil
            print("[VoicePipeline] Previous session memory save complete")
        }

        let memory = MemoryService(
            storageService: storageService,
            geminiService: geminiService,
            userId: userId
        )
        await memory.loadMemories()

        let sessionStore = storageService.map { FirestoreLiveCheckInSessionStore(storageService: $0) }
        let guidance = UnifiedGuidanceService(
            geminiService: geminiService,
            memoryService: memory,
            sessionStore: sessionStore,
            userId: userId
        )

        // Build unified system prompt with memory context
        let memoryContext = memory.buildContextString()
        var sessionContext = PromptService.buildSessionContext()

        // Append unread voice messages to session context
        if let vmService = voiceMessageInboxService {
            let unread = vmService.messages.filter { $0.isUnread }
            if !unread.isEmpty {
                let vmSummary = unread.map { msg in
                    let sender = msg.caregiverName ?? "Caregiver"
                    let dur = Int(msg.durationSeconds)
                    return "- From \"\(sender)\", \(dur)s, ID: \(msg.id ?? "unknown")"
                }.joined(separator: "\n")
                sessionContext += "\n\n[Unread voice messages (\(unread.count)):\n\(vmSummary)\nMention these naturally. Ask if they want to listen. Use play_voice_message tool when they say yes.]"
            }
        }

        let systemPrompt = PromptService.renderUnifiedSystemPrompt(
            companionName: companionName,
            memoryContext: memoryContext,
            sessionContext: sessionContext
        )

        // Configure Gemini Live with unified prompt + tools
        geminiLiveService.systemInstruction = systemPrompt
        geminiLiveService.extraFunctionDeclarations = UnifiedGuidanceService.unifiedToolDeclarations + defaultExtraTools

        self.memoryService = memory
        self.guidanceService = guidance
        self.unifiedGuidanceActive = true
        self.unifiedSessionCompletionTask = nil

        print(
            "[VoicePipeline] Unified session prepared (memory context: \(MemoryBudget.estimateTokens(memoryContext)) tokens, session context: \(MemoryBudget.estimateTokens(sessionContext)) tokens)"
        )
        return true
    }

    /// Handle session completion: extract memories from transcript, consolidate.
    private func handleSessionComplete(
        guidance: UnifiedGuidanceService,
        memory: MemoryService,
        transcript: [(role: String, text: String)]
    ) async {
        guard !transcript.isEmpty else { return }

        _ = await guidance.handleCompleteSession()

        // Sync check-in to backend graph if available
        if let checkIn = guidance.completedCheckIn,
           let extraction = guidance.latestExtractionResult {
            Task { await self.graphSyncService?.syncCheckIn(checkIn, extraction: extraction) }
        }

        if let memoryProjectionService {
            await memoryProjectionService.drainPendingMemoryProjections(using: memory)
        } else {
            if let delta = await memory.extractMemories(transcript: transcript) {
                await memory.applyDelta(delta)
            }
            await memory.consolidateMemories()
        }

        print("[VoicePipeline] Session memories saved (\(memory.episodicMemories.count) episodic, \(memory.semanticPatterns.count) semantic)")
    }

    /// Hint that a check-in should start (e.g., user tapped Check In button in unified mode).
    func suggestUnifiedCheckIn() {
        guidanceService?.suggestCheckIn()
    }

    func completeUnifiedSessionToolCall(
        id: String,
        guidance: UnifiedGuidanceService,
        memory: MemoryService
    ) async {
        let coordinator = makeUnifiedSessionCompletionCoordinator()
        let transcript = guidance.transcript

        await coordinator.finish(id: id) {
            guard !transcript.isEmpty else { return }

            if self.unifiedSessionCompletionTask == nil {
                self.unifiedSessionCompletionTask = Task { @MainActor [weak self, guidance, memory, transcript] in
                    await self?.handleSessionComplete(
                        guidance: guidance,
                        memory: memory,
                        transcript: transcript
                    )
                }
            }

            await self.unifiedSessionCompletionTask?.value
        }
    }

    private func requestStopSession() {
        if let stopSessionOverride {
            stopSessionOverride()
        } else {
            stop()
        }
    }

    private func makeUnifiedSessionCompletionCoordinator() -> UnifiedSessionCompletionCoordinator {
        UnifiedSessionCompletionCoordinator(
            sendToolResponse: { [weak self] id, response, completion in
                guard let self else {
                    completion()
                    return
                }
                if let toolResponseSender = self.toolResponseSender {
                    toolResponseSender(id, response, completion)
                } else {
                    self.geminiLiveService.sendToolResponse(
                        id: id,
                        response: response,
                        completion: completion
                    )
                }
            },
            stopSession: { [weak self] in
                self?.requestStopSession()
            }
        )
    }

    private func finalizeCompanionSessionTurnIfNeeded() async {
        guard guidanceService == nil, liveCheckInManager == nil else { return }

        if !pendingUserTranscript.isEmpty {
            await recordCompanionTurn(role: .user, text: pendingUserTranscript)
        }

        let assistantText = pendingAssistantTranscript.isEmpty ? pendingModelText : pendingAssistantTranscript
        if !assistantText.isEmpty {
            await recordCompanionTurn(role: .assistant, text: assistantText)
        }
    }

    private func recordCompanionTurn(role: ConversationEntry.Role, text: String) async {
        guard let userId, !userId.isEmpty else { return }
        guard guidanceService == nil, liveCheckInManager == nil else { return }

        let recorder = ensureCompanionSessionRecorder()
        let source = currentCompanionProjectionSource()
        let intent = currentCompanionProjectionIntent()

        switch role {
        case .user:
            await recorder.recordUserUtterance(text, source: source, intent: intent)
        case .assistant:
            await recorder.recordAssistantUtterance(text, source: source, intent: intent)
        }
    }

    private func recordCreativeArtifactIfNeeded(from result: CreativeResult?) async {
        guard let result else { return }

        if let guidanceService {
            await guidanceService.recordCreativeArtifact(
                mediaType: result.mediaType,
                prompt: result.prompt
            )
            return
        }

        guard liveCheckInManager == nil, let userId, !userId.isEmpty else { return }
        let recorder = ensureCompanionSessionRecorder()
        await recorder.recordCreativeArtifact(
            mediaType: result.mediaType,
            prompt: result.prompt,
            source: "creative",
            intent: "creative"
        )
    }

    private func ensureCompanionSessionRecorder() -> CompanionSessionProjectionRecorder {
        if let companionSessionRecorder {
            return companionSessionRecorder
        }

        let recorder = CompanionSessionProjectionRecorder(
            sessionStore: storageService.map { FirestoreLiveCheckInSessionStore(storageService: $0) },
            userId: userId
        )
        companionSessionRecorder = recorder
        return recorder
    }

    private func currentCompanionProjectionSource() -> String {
        if reportFlowCoordinator?.isActive == true { return "report" }
        if creativeFlowManager?.flowState != .idle { return "creative" }
        if checkInCoordinator?.isCheckInActive == true { return "scripted_checkin" }
        switch pipelineMode {
        case .local:
            return "local"
        case .live, .liveText:
            return "live"
        }
    }

    private func currentCompanionProjectionIntent() -> String? {
        if reportFlowCoordinator?.isActive == true { return "report" }
        if creativeFlowManager?.flowState != .idle { return "creative" }
        if checkInCoordinator?.isCheckInActive == true { return "checkin" }
        return "casual"
    }

    private func queueCreativeStatusAnnouncement(_ message: String) {
        guard !message.isEmpty else { return }
        pendingCreativeStatusAnnouncement = message
        flushPendingCreativeStatusAnnouncementIfPossible()
    }

    private func flushPendingCreativeStatusAnnouncementIfPossible() {
        guard let message = pendingCreativeStatusAnnouncement else { return }
        guard isRunning else { return }
        guard pipelineMode == .live || pipelineMode == .liveText else { return }
        guard liveConnectionState == .ready else { return }
        guard state == .listening else { return }
        guard pendingUserTranscript.isEmpty,
              pendingAssistantTranscript.isEmpty,
              pendingModelText.isEmpty else {
            return
        }

        pendingCreativeStatusAnnouncement = nil
        geminiLiveService.sendText(
            "System event: \(message) Tell the person in one short friendly sentence."
        )
    }

    func playVoiceMessage(_ message: VoiceMessage) {
        guard let audioData = Data(base64Encoded: message.audioBase64) else { return }
        var result = CreativeResult(mediaType: .voiceMessage, audioData: audioData, prompt: "")
        result.senderName = message.caregiverName
        result.transcript = message.transcript
        result.messageId = message.id
        result.isUnread = message.isUnread

        creativeCanvas = CreativeCanvasState(
            artifactId: message.id ?? UUID().uuidString,
            mediaType: .voiceMessage,
            prompt: message.caregiverName ?? "Caregiver",
            status: .ready,
            statusMessage: "",
            result: result,
            isVisible: true
        )
        creativeResult = result
    }

    func dismissCreativeCanvas() {
        if creativeCanvas?.mediaType == .voiceMessage {
            creativeCanvas = nil
            creativeResult = nil
            return
        }
        creativeFlowManager?.closeCanvas()
        creativeCanvas = creativeFlowManager?.canvasState
        creativeResult = creativeCanvas?.result
    }

    /// Public accessor for injecting captured photos from the UI layer.
    func ensureCreativeFlowManagerForInjection() -> CreativeFlowManager {
        ensureCreativeFlowManager()
    }

    // MARK: - Phone Camera Helpers

    /// Capture from phone camera, send to Gemini, inject into canvas, close preview.
    func captureAndSendPhoto(camera: PhoneCameraService.CameraPosition, cameraStr: String) async {
        guard let phoneCamera = phoneCameraService else { return }

        let photo = await phoneCamera.capturePhoto()
        cameraPreviewActive = false
        phoneCamera.stop()
        cameraAutoCaptureTasks.removeValue(forKey: cameraStr)

        if let photo {
            sendCapturedPhotoToGemini(photo)
            let manager = ensureCreativeFlowManager()
            let prompt = cameraStr == "front" ? "Selfie" : "Photo"
            manager.injectCapturedImage(photo, prompt: prompt)
        }
    }

    /// Send a captured photo to Gemini Live as an image + text notification.
    func sendCapturedPhotoToGemini(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return }
        geminiLiveService.sendImage(jpegData)
        geminiLiveService.sendText("[Photo captured from iPhone camera. The photo is now in your image stream. Describe it if asked.]")
    }

    enum PipelineError: LocalizedError, Equatable {
        case notInitialized
        case ttsNotReady
        case voiceConsentRequired

        var errorDescription: String? {
            switch self {
            case .notInitialized:
                return "Pipeline not initialized. Call initializeModels() first."
            case .ttsNotReady:
                return "TTS model not ready. Required for Live+TTS mode."
            case .voiceConsentRequired:
                return "Voice processing consent is required for live audio streaming."
            }
        }
    }
}
