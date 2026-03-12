import Foundation

/// WebSocket client for Lyria RealTime (BidiGenerateMusic) streaming music API.
/// Streams 44.1kHz stereo 16-bit PCM audio chunks from the server.
final class LyriaRealtimeService {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case settingUp
        case ready
        case paused
        case error(String)
    }

    enum PlaybackCommand: String {
        case play = "PLAY"
        case pause = "PAUSE"
        case stop = "STOP"
        case resetContext = "RESET_CONTEXT"
    }

    struct WeightedPrompt {
        let text: String
        let weight: Double
    }

    struct MusicConfig {
        var bpm: Int?
        var brightness: Double?
        var density: Double?
        var guidance: Double?
        var temperature: Double?
        var muteBass: Bool?
        var muteDrums: Bool?
    }

    // MARK: - Callbacks

    var onConnectionStateChanged: ((ConnectionState) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onFilteredPrompt: ((String) -> Void)?

    // MARK: - State

    private(set) var state: ConnectionState = .disconnected
    private var webSocketTask: URLSessionWebSocketTask?
    private var connectionEpoch = 0
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 24 * 60 * 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: config)
    }()

    // MARK: - Connection

    func connect() {
        guard state == .disconnected || isErrorState else { return }

        connectionEpoch += 1
        let epoch = connectionEpoch

        let urlString = "\(Config.lyriaRealtimeBaseURL)?key=\(Config.geminiAPIKey)"
        guard let url = URL(string: urlString) else {
            updateState(.error("Invalid WebSocket URL"))
            return
        }

        updateState(.connecting)

        var request = URLRequest(url: url)
        request.timeoutInterval = 24 * 60 * 60
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        sendJSON(buildSetupMessage())
        updateState(.settingUp)
        receiveLoop(epoch: epoch)
        print("[LyriaRealtime] Connecting — epoch=\(epoch), url=\(Config.lyriaRealtimeBaseURL)")
    }

    func disconnect() {
        let oldEpoch = connectionEpoch
        connectionEpoch += 1
        print("[LyriaRealtime] disconnect() — epoch \(oldEpoch)→\(connectionEpoch)")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        updateState(.disconnected)
    }

    // MARK: - Controls

    func setWeightedPrompts(_ prompts: [WeightedPrompt]) {
        guard state == .ready || state == .paused else { return }
        sendJSON(buildWeightedPromptsMessage(prompts))
    }

    func setMusicConfig(_ config: MusicConfig) {
        guard state == .ready || state == .paused else { return }
        sendJSON(buildMusicConfigMessage(config))
    }

    func play() {
        guard state == .ready || state == .paused else { return }
        sendJSON(buildPlaybackMessage(.play))
    }

    func pause() {
        guard state == .ready else { return }
        sendJSON(buildPlaybackMessage(.pause))
        updateState(.paused)
    }

    func stop() {
        guard state == .ready || state == .paused else { return }
        sendJSON(buildPlaybackMessage(.stop))
    }

    func resetContext() {
        guard state == .ready || state == .paused else { return }
        sendJSON(buildPlaybackMessage(.resetContext))
    }

    // MARK: - Message Builders (internal for testing)

    func buildSetupMessage() -> [String: Any] {
        [
            "setup": [
                "model": "models/\(Config.lyriaRealtimeModel)"
            ]
        ]
    }

    /// Raw protocol: `{ "clientContent": { "weightedPrompts": [...] } }`
    func buildWeightedPromptsMessage(_ prompts: [WeightedPrompt]) -> [String: Any] {
        [
            "clientContent": [
                "weightedPrompts": prompts.map { prompt in
                    [
                        "text": prompt.text,
                        "weight": prompt.weight,
                    ] as [String: Any]
                }
            ]
        ]
    }

    /// Raw protocol: `{ "musicGenerationConfig": { ... } }`
    func buildMusicConfigMessage(_ config: MusicConfig) -> [String: Any] {
        var musicConfig: [String: Any] = [:]
        if let bpm = config.bpm { musicConfig["bpm"] = bpm }
        if let brightness = config.brightness { musicConfig["brightness"] = brightness }
        if let density = config.density { musicConfig["density"] = density }
        if let guidance = config.guidance { musicConfig["guidance"] = guidance }
        if let temperature = config.temperature { musicConfig["temperature"] = temperature }
        if let muteBass = config.muteBass { musicConfig["mute_bass"] = muteBass }
        if let muteDrums = config.muteDrums { musicConfig["mute_drums"] = muteDrums }

        return ["musicGenerationConfig": musicConfig]
    }

    /// Raw protocol: `{ "playbackControl": "PLAY" }`
    func buildPlaybackMessage(_ command: PlaybackCommand) -> [String: Any] {
        ["playbackControl": command.rawValue]
    }

    // MARK: - Message Handling (internal for testing)

    func handleMessage(_ json: [String: Any]) {
        if json["setupComplete"] != nil {
            print("[LyriaRealtime] Setup complete — ready")
            updateState(.ready)
            return
        }

        if let serverContent = json["serverContent"] as? [String: Any] {
            if let audioChunks = serverContent["audioChunks"] as? [[String: Any]] {
                for chunk in audioChunks {
                    if let base64 = chunk["data"] as? String,
                       let audioData = Data(base64Encoded: base64) {
                        onAudioChunk?(audioData)
                    }
                }
            }

            if let filtered = serverContent["filteredPrompt"] as? String {
                print("[LyriaRealtime] Prompt filtered: \(filtered)")
                onFilteredPrompt?(filtered)
            }
            return
        }

        // Log the full message for debugging connection issues
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print("[LyriaRealtime] Unhandled message: \(str.prefix(500))")
        } else {
            let keys = json.keys.joined(separator: ", ")
            print("[LyriaRealtime] Unhandled message keys: \(keys)")
        }
    }

    // MARK: - Test Helpers

    func testSetState(_ newState: ConnectionState) {
        state = newState
    }

    // MARK: - Private

    private func receiveLoop(epoch: Int) {
        webSocketTask?.receive { [weak self] result in
            guard let self, self.connectionEpoch == epoch else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.handleMessage(json)
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.handleMessage(json)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop(epoch: epoch)

            case .failure(let error):
                print("[LyriaRealtime] WebSocket error (epoch=\(epoch)): \(error.localizedDescription)")
                if self.connectionEpoch == epoch {
                    self.updateState(.error(error.localizedDescription))
                }
            }
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            print("[LyriaRealtime] Failed to serialize JSON")
            return
        }

        print("[LyriaRealtime] Sending: \(string.prefix(200))")
        webSocketTask?.send(.string(string)) { error in
            if let error {
                print("[LyriaRealtime] Send error: \(error.localizedDescription)")
            }
        }
    }

    private func updateState(_ newState: ConnectionState) {
        let old = state
        state = newState
        print("[LyriaRealtime] state: \(old) → \(newState)")
        onConnectionStateChanged?(newState)
    }

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }
}
