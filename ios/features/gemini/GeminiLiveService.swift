import Foundation

/// WebSocket client for Gemini Live (BidiGenerateContent) native audio API.
/// Streams 16kHz PCM audio in, receives 24kHz PCM audio + text transcripts out.
final class GeminiLiveService {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case settingUp
        case ready
        case error(String)
    }

    // MARK: - Callbacks (called from background — callers must dispatch to main)

    var onConnectionStateChanged: ((ConnectionState) -> Void)?
    /// Raw PCM Int16 audio chunk at 24kHz mono little-endian
    var onAudioOutput: ((Data) -> Void)?
    /// Transcript of user speech (from server-side ASR)
    var onInputTranscript: ((String) -> Void)?
    /// Transcript of model speech
    var onOutputTranscript: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    /// Function call from model (e.g. "look" for camera)
    var onToolCall: ((String, String, [String: Any]) -> Void)?  // (id, name, args)

    /// Streaming text chunks from model turn (used in TEXT response mode)
    var onModelText: ((String) -> Void)?

    // MARK: - Configuration

    /// When true, server returns native audio. When false, returns text (for on-device TTS).
    var useNativeAudio: Bool = true
    var voiceName: String = "Puck"
    var systemInstruction: String = PromptService.companionSystemPrompt

    /// Additional function declarations merged into tools during setup.
    /// Set before calling connect() to add check-in or other tools.
    var extraFunctionDeclarations: [[String: Any]] = []

    // MARK: - State

    private(set) var state: ConnectionState = .disconnected
    private var webSocketTask: URLSessionWebSocketTask?
    /// Monotonically increasing epoch — incremented on every connect/disconnect.
    /// Prevents cancelled WebSocket receive handlers from corrupting state.
    private var connectionEpoch = 0
    /// Tracks audio drops for throttled logging
    private var audioDropCount = 0
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var autoReconnectAttempts = 0
    private var autoReconnectEnabled = false
    private var isManualDisconnect = false
    private let maxAutoReconnectAttempts = 1
    private let heartbeatIntervalNanoseconds: UInt64 = 20_000_000_000
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 24 * 60 * 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: config)
    }()

    // MARK: - Connection

    func connect() {
        openConnection(resetReconnectAttempts: true)
    }

    private func openConnection(
        resetReconnectAttempts: Bool,
        force: Bool = false
    ) {
        print("[GeminiLive] connect() — state=\(state), epoch=\(connectionEpoch)")
        guard force || state == .disconnected || isErrorState else {
            print("[GeminiLive] connect() SKIPPED — guard failed (state=\(state))")
            return
        }

        if resetReconnectAttempts {
            autoReconnectAttempts = 0
        }
        autoReconnectEnabled = true
        isManualDisconnect = false
        reconnectTask?.cancel()
        stopHeartbeat()

        connectionEpoch += 1
        let epoch = connectionEpoch
        print("[GeminiLive] connect() proceeding — epoch=\(epoch)")

        let urlString = "\(Config.geminiLiveBaseURL)?key=\(Config.geminiAPIKey)"
        guard let url = URL(string: urlString) else {
            updateState(.error("Invalid WebSocket URL"))
            return
        }

        updateState(.connecting)

        var request = URLRequest(url: url)
        request.timeoutInterval = 24 * 60 * 60
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        // Send setup immediately
        sendSetupMessage()
        receiveLoop(epoch: epoch)
    }

    func disconnect() {
        isManualDisconnect = true
        autoReconnectEnabled = false
        reconnectTask?.cancel()
        reconnectTask = nil
        stopHeartbeat()
        let oldEpoch = connectionEpoch
        connectionEpoch += 1
        print("[GeminiLive] disconnect() — epoch \(oldEpoch)→\(connectionEpoch), state=\(state)")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        audioDropCount = 0
        updateState(.disconnected)
    }

    // MARK: - Send Audio

    /// Send audio samples to Gemini Live. Converts Float32 [-1,1] → Int16 PCM → base64.
    func sendAudio(_ samples: [Float]) {
        guard state == .ready else {
            audioDropCount += 1
            if audioDropCount == 1 || audioDropCount % 200 == 0 {
                print("[GeminiLive] sendAudio DROPPED #\(audioDropCount) — state=\(state)")
            }
            return
        }
        if audioDropCount > 0 {
            print("[GeminiLive] sendAudio RESUMED after \(audioDropCount) drops")
            audioDropCount = 0
        }

        let int16Data = float32ToInt16PCM(samples)
        let base64 = int16Data.base64EncodedString()

        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [[
                    "mimeType": "audio/pcm;rate=16000",
                    "data": base64
                ]]
            ]
        ]

        sendJSON(message)
    }

    // MARK: - Send Image

    /// Send a JPEG image frame to Gemini Live for vision.
    func sendImage(_ jpegData: Data) {
        guard state == .ready else { return }

        let base64 = jpegData.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "video": [
                    "mimeType": "image/jpeg",
                    "data": base64
                ]
            ]
        ]

        sendJSON(message)
    }

    // MARK: - Send Text

    /// Signal that the client turn is complete without sending content.
    /// This gives Gemini the floor to speak first (e.g. proactive greeting).
    func sendTurnComplete() {
        guard state == .ready else { return }

        let message: [String: Any] = [
            "clientContent": [
                "turnComplete": true
            ]
        ]

        sendJSON(message)
    }

    /// Send a text turn to Gemini Live via clientContent.
    /// Uses the non-realtime text input path instead of streaming audio.
    func sendText(_ text: String) {
        guard state == .ready else { return }

        let message: [String: Any] = [
            "clientContent": [
                "turns": [[
                    "role": "user",
                    "parts": [["text": text]]
                ]],
                "turnComplete": true
            ]
        ]

        sendJSON(message)
    }

    // MARK: - Send Tool Response

    func sendToolResponse(
        id: String,
        response: [String: Any],
        completion: (() -> Void)? = nil
    ) {
        print("[GeminiLive] sendToolResponse id=\(id)")
        let message: [String: Any] = [
            "toolResponse": [
                "functionResponses": [[
                    "id": id,
                    "response": response
                ]]
            ]
        ]
        sendJSON(message, completion: completion)
    }

    // MARK: - Private — Setup

    private func sendSetupMessage() {
        var generationConfig: [String: Any] = [
            "temperature": 0.7
        ]

        if useNativeAudio {
            generationConfig["responseModalities"] = ["AUDIO"]
            generationConfig["speechConfig"] = [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": voiceName
                    ]
                ]
            ] as [String: Any]
        } else {
            generationConfig["responseModalities"] = ["TEXT"]
        }

        var setupBody: [String: Any] = [
            "model": "models/\(Config.geminiLiveModel)",
            "generationConfig": generationConfig,
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ],
            "tools": toolDeclarations,
            "inputAudioTranscription": [String: Any](),
            "realtimeInputConfig": [
                "automaticActivityDetection": [
                    "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                    "prefixPaddingMs": 20,
                    "silenceDurationMs": 300
                ]
            ]
        ]

        // Only request output transcription in audio mode (text mode already returns text)
        if useNativeAudio {
            setupBody["outputAudioTranscription"] = [String: Any]()
        }

        let setup: [String: Any] = ["setup": setupBody]

        updateState(.settingUp)
        sendJSON(setup)
        let mode = useNativeAudio ? "AUDIO" : "TEXT"
        let toolNames = extraFunctionDeclarations.compactMap { $0["name"] as? String }
        print("[GeminiLive] Setup sent: model=\(Config.geminiLiveModel), mode=\(mode), voice=\(voiceName), tools=[\(toolNames.joined(separator: ","))]")
    }

    private var toolDeclarations: [[String: Any]] {
        var declarations: [[String: Any]] = [[
            "name": "look",
            "description": "Look through the smart glasses camera to see what the user is seeing. Use this whenever the user asks to look at, describe, identify, or read something.",
            "parameters": [
                "type": "OBJECT",
                "properties": [String: Any]()
            ] as [String: Any]
        ]]
        declarations.append(contentsOf: extraFunctionDeclarations)
        return [
            ["functionDeclarations": declarations],
            ["google_search": [String: Any]()]
        ]
    }

    // MARK: - Private — Receive Loop

    private func receiveLoop(epoch: Int) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            guard self.connectionEpoch == epoch else {
                print("[GeminiLive] receiveLoop STALE — epoch=\(epoch) vs current=\(self.connectionEpoch), ignoring")
                return
            }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleMessage(data)
                    }
                case .data(let data):
                    self.handleMessage(data)
                @unknown default:
                    break
                }
                // Continue receiving
                self.receiveLoop(epoch: epoch)

            case .failure(let error):
                let msg = error.localizedDescription
                print("[GeminiLive] WebSocket receive error (epoch=\(epoch)): \(msg)")
                // Only set error if this epoch is still current
                if self.connectionEpoch == epoch {
                    self.attemptAutoReconnect(reason: msg, expectedEpoch: epoch)
                } else {
                    print("[GeminiLive] Ignoring stale error (epoch=\(epoch) vs current=\(self.connectionEpoch))")
                }
            }
        }
    }

    // MARK: - Private — Message Handling

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[GeminiLive] Failed to parse message")
            return
        }

        // Setup complete
        if json["setupComplete"] != nil {
            print("[GeminiLive] Setup complete — ready (epoch=\(connectionEpoch))")
            autoReconnectAttempts = 0
            updateState(.ready)
            startHeartbeat(epoch: connectionEpoch)
            return
        }

        // Server content (audio, transcripts, turn management)
        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
            return
        }

        // Tool call from model
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for fc in functionCalls {
                if let id = fc["id"] as? String,
                   let name = fc["name"] as? String {
                    let args = fc["args"] as? [String: Any] ?? [:]
                    print("[GeminiLive] Tool call: \(name)(id=\(id))")
                    onToolCall?(id, name, args)
                }
            }
            return
        }

        // Log unexpected message types
        let keys = json.keys.joined(separator: ", ")
        print("[GeminiLive] Unhandled message keys: \(keys)")
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Interruption — user started speaking, stop playback
        if let interrupted = content["interrupted"] as? Bool, interrupted {
            print("[GeminiLive] Interrupted")
            onInterrupted?()
            return
        }

        // Turn complete — model finished responding
        if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
            print("[GeminiLive] Turn complete")
            onTurnComplete?()
            return
        }

        // Input transcription (what the user said)
        if let inputTranscription = content["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String,
           !text.isEmpty {
            print("[GeminiLive] User: \(text)")
            onInputTranscript?(text)
        }

        // Output transcription (what the model said)
        if let outputTranscription = content["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String,
           !text.isEmpty {
            print("[GeminiLive] Model: \(text)")
            onOutputTranscript?(text)
        }

        // Model turn with audio/text data
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                // Audio output (native audio mode)
                if let inlineData = part["inlineData"] as? [String: Any],
                   let base64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: base64) {
                    onAudioOutput?(audioData)
                }
                // Text output (text response mode)
                if let text = part["text"] as? String {
                    onModelText?(text)
                }
            }
        }
    }

    // MARK: - Private — Helpers

    private func sendJSON(
        _ dict: [String: Any],
        completion: (() -> Void)? = nil
    ) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            print("[GeminiLive] Failed to serialize JSON")
            return
        }

        webSocketTask?.send(.string(string)) { error in
            if let error = error {
                print("[GeminiLive] Send error: \(error.localizedDescription)")
                self.attemptAutoReconnect(reason: error.localizedDescription, expectedEpoch: self.connectionEpoch)
            }
            completion?()
        }
    }

    private func updateState(_ newState: ConnectionState) {
        let old = state
        state = newState
        print("[GeminiLive] state: \(old) → \(newState) (epoch=\(connectionEpoch))")
        onConnectionStateChanged?(newState)
    }

    private func float32ToInt16PCM(_ samples: [Float]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<samples.count {
                let clamped = max(-1.0, min(1.0, samples[i]))
                int16Buffer[i] = Int16(clamped * 32767.0)
            }
        }
        return data
    }

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }

    private func startHeartbeat(epoch: Int) {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: heartbeatIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                guard self.connectionEpoch == epoch else { break }
                guard self.state == .ready else { continue }

                self.webSocketTask?.sendPing { [weak self] error in
                    guard let self else { return }
                    if let error {
                        print("[GeminiLive] Ping failed: \(error.localizedDescription)")
                        self.attemptAutoReconnect(reason: error.localizedDescription, expectedEpoch: epoch)
                    }
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func attemptAutoReconnect(
        reason: String,
        expectedEpoch: Int
    ) {
        guard connectionEpoch == expectedEpoch else { return }
        guard autoReconnectEnabled, !isManualDisconnect else {
            updateState(.error(reason))
            return
        }
        guard autoReconnectAttempts < maxAutoReconnectAttempts else {
            updateState(.error(reason))
            return
        }

        autoReconnectAttempts += 1
        print("[GeminiLive] Attempting auto-reconnect #\(autoReconnectAttempts) after error: \(reason)")
        stopHeartbeat()
        reconnectTask?.cancel()
        let oldEpoch = connectionEpoch
        connectionEpoch += 1
        print("[GeminiLive] autoReconnect invalidated epoch \(oldEpoch)→\(connectionEpoch)")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        audioDropCount = 0
        updateState(.connecting)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            guard self.autoReconnectEnabled, !self.isManualDisconnect else { return }
            self.openConnection(resetReconnectAttempts: false, force: true)
        }
    }
}
