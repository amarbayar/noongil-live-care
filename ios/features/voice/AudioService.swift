import Foundation
import AVFoundation

/// Handles HFP audio capture from glasses mic and TTS playback to glasses speakers.
/// Capture: 8kHz mono HFP → resample to 16kHz → Float32 samples for VAD/ASR.
/// Playback: Float32 PCM from TTS → AVAudioPlayerNode → glasses speaker.
final class AudioService: ObservableObject {
    @Published var isCapturing = false
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var inputSampleRate: Double = 0

    /// Current pipeline mode — determines audio session configuration
    var pipelineMode: PipelineMode = .local

    /// Callback invoked with 16kHz Float32 audio chunks from the microphone
    var onAudioChunk: (([Float]) -> Void)?

    /// Callback invoked with normalized RMS audio level (0.0–1.0) for visual feedback
    var onAudioLevel: ((Float) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioConverter: AVAudioConverter?
    private var isPlayerAttached = false
    private var streamingFormat: AVAudioFormat?

    /// Target sample rate for ASR/VAD
    private let targetSampleRate: Double = 16_000

    struct SessionStrategy: Equatable {
        let sessionMode: AVAudioSession.Mode
        let categoryOptions: AVAudioSession.CategoryOptions
        let engineVoiceProcessingEnabled: Bool
    }

    // MARK: - Audio Session

    /// Configure AVAudioSession for the current pipeline mode.
    /// - **Local**: `.voiceChat` mode — negotiates mSBC wideband (16kHz) and provides AEC/NS/AGC.
    ///   Local ASR benefits from the built-in noise suppression.
    /// - **Live/LiveText**: `.default` mode — avoids the heavy voice-processing overhead of `.voiceChat`.
    ///   Gemini handles noise server-side, so client-side NS/AGC is unnecessary and adds latency.
    /// Call this BEFORE starting camera stream.
    func configureAudioSession(for mode: PipelineMode) throws {
        pipelineMode = mode
        let session = AVAudioSession.sharedInstance()
        print("[AudioService] configureAudioSession(mode: \(mode.rawValue)) — current category=\(session.category.rawValue), mode=\(session.mode.rawValue)")
        let hasBluetooth = Self.hasBluetoothInput(in: session.currentRoute)
        let strategy = Self.makeSessionStrategy(for: mode, hasBluetoothInput: hasBluetooth)

        try session.setCategory(
            .playAndRecord,
            mode: strategy.sessionMode,
            options: strategy.categoryOptions
        )
        try session.setPreferredSampleRate(16_000)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Hint to the system to prefer echo-cancelled mic input
        if #available(iOS 18.2, macCatalyst 18.2, *) {
            try session.setPrefersEchoCancelledInput(true)
        }

        let route = session.currentRoute

        // Enable engine-level VoiceProcessingIO for built-in mic + speaker (non-Bluetooth)
        // to provide hardware AEC. Without this, Gemini hears its own output from the
        // speaker and self-interrupts. Bluetooth HFP handles AEC in the codec.
        let inputNode = audioEngine.inputNode
        if inputNode.isVoiceProcessingEnabled != strategy.engineVoiceProcessingEnabled {
            try inputNode.setVoiceProcessingEnabled(strategy.engineVoiceProcessingEnabled)
            print("[AudioService] Voice processing: \(strategy.engineVoiceProcessingEnabled) (bluetooth=\(hasBluetooth), mode=\(mode.rawValue))")
        }

        let inputs = route.inputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
        let outputs = route.outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
        print("[AudioService] Session active — sampleRate=\(session.sampleRate), inputs=[\(inputs)], outputs=[\(outputs)], voiceProcessing=\(inputNode.isVoiceProcessingEnabled), sessionMode=\(strategy.sessionMode.rawValue)")
    }

    // MARK: - Capture

    /// Start capturing audio from the microphone (glasses HFP or device mic).
    /// Resamples to 16kHz and delivers Float32 chunks via `onAudioChunk`.
    func startCapture() throws {
        guard !isCapturing else {
            print("[AudioService] startCapture SKIPPED — already capturing")
            return
        }

        let inputNode = audioEngine.inputNode
        print("[AudioService] startCapture — voiceProcessing=\(inputNode.isVoiceProcessingEnabled)")

        // Voice processing was already configured in configureAudioSession().
        // Fetch the current input format (reflects VP state).
        var inputFormat = inputNode.outputFormat(forBus: 0)
        print("[AudioService] inputFormat: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount), commonFormat=\(inputFormat.commonFormat.rawValue)")

        // Guard against invalid format (0 sample rate = no audio route)
        guard inputFormat.sampleRate > 0 else {
            print("[AudioService] ERROR: inputFormat.sampleRate is 0 — no audio input route available")
            throw NSError(domain: "AudioService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio input available (sample rate 0)"])
        }

        // Publish actual input sample rate for diagnostics (shows negotiated codec)
        DispatchQueue.main.async { self.inputSampleRate = inputFormat.sampleRate }

        // Prepare resampler if input isn't already 16kHz
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
            print("[AudioService] Resampler: \(inputFormat.sampleRate)Hz → \(targetSampleRate)Hz")
        } else {
            audioConverter = nil
            print("[AudioService] No resampling needed (already 16kHz mono)")
        }

        // Attach player node for TTS playback (only once)
        if !isPlayerAttached {
            audioEngine.attach(playerNode)
            isPlayerAttached = true
        }
        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: outputFormat)

        // Install tap on input for capture
        let bufferSize: AVAudioFrameCount = 1024
        var tapCallCount = 0
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            tapCallCount += 1
            if tapCallCount == 1 {
                print("[AudioService] TAP: first buffer — frames=\(buffer.frameLength), sampleRate=\(buffer.format.sampleRate), time=\(time.sampleTime)")
            } else if tapCallCount % 500 == 0 {
                print("[AudioService] TAP: buffer #\(tapCallCount)")
            }
            self?.processInputBuffer(buffer)
        }
        print("[AudioService] installTap done, calling audioEngine.start()...")

        try audioEngine.start()

        // setVoiceProcessingEnabled can leave the engine in a state where start()
        // succeeds (no error) but isRunning stays false. Detect and retry.
        if !audioEngine.isRunning {
            print("[AudioService] audioEngine.start() returned but isRunning=false — retrying...")
            inputNode.removeTap(onBus: 0)

            // Re-fetch format after the failed start (voice processing graph may have settled)
            inputFormat = inputNode.outputFormat(forBus: 0)
            print("[AudioService] Retry inputFormat: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount)")

            if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
                audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
            } else {
                audioConverter = nil
            }

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
                tapCallCount += 1
                if tapCallCount == 1 {
                    print("[AudioService] TAP: first buffer — frames=\(buffer.frameLength), sampleRate=\(buffer.format.sampleRate), time=\(time.sampleTime)")
                } else if tapCallCount % 500 == 0 {
                    print("[AudioService] TAP: buffer #\(tapCallCount)")
                }
                self?.processInputBuffer(buffer)
            }

            try audioEngine.start()
            print("[AudioService] Retry audioEngine.start() — isRunning=\(audioEngine.isRunning)")
        } else {
            print("[AudioService] audioEngine.start() succeeded — isRunning=true")
        }

        DispatchQueue.main.async { self.isCapturing = true }
    }

    /// Stop audio capture.
    func stopCapture() {
        guard isCapturing else { return }
        print("[AudioService] stopCapture — processBufferCallCount=\(processBufferCallCount)")
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        processBufferCallCount = 0
        DispatchQueue.main.async {
            self.isCapturing = false
            self.isPlaying = false
        }
    }

    // MARK: - Playback

    /// Play TTS audio through the glasses speaker (or default output).
    /// - Parameters:
    ///   - samples: Float32 PCM samples from TTS
    ///   - sampleRate: Sample rate of TTS output (e.g., 22050)
    ///   - completion: Called when playback finishes
    func playTTSAudio(samples: [Float], sampleRate: Int, completion: (() -> Void)? = nil) {
        guard !samples.isEmpty else {
            completion?()
            return
        }

        let ttsSampleRate = Double(sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: ttsSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            completion?()
            return
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            completion?()
            return
        }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channelData.update(from: src.baseAddress!, count: samples.count)
            }
        }

        // If player isn't connected at TTS sample rate, reconnect
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        DispatchQueue.main.async { self.isPlaying = true }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
                completion?()
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Schedule a chunk of Int16 PCM audio for streaming playback (Gemini Live).
    /// Chunks are queued and played sequentially by AVAudioPlayerNode.
    func scheduleAudioChunk(int16Data: Data, sampleRate: Int) {
        let sampleCount = int16Data.count / 2
        guard sampleCount > 0 else { return }

        let rate = Double(sampleRate)

        // Set up or switch format if needed
        if streamingFormat == nil || streamingFormat!.sampleRate != rate {
            guard let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: rate,
                channels: 1,
                interleaved: false
            ) else { return }
            streamingFormat = fmt
            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: fmt)
        }

        guard let format = streamingFormat else { return }

        let frameCount = AVAudioFrameCount(sampleCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            int16Data.withUnsafeBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    channelData[i] = Float(int16Buffer[i]) / 32768.0
                }
            }
        }

        playerNode.scheduleBuffer(buffer)

        if !playerNode.isPlaying {
            playerNode.play()
        }

        DispatchQueue.main.async { self.isPlaying = true }
    }

    /// Stop any ongoing TTS playback (also clears streaming queue).
    func stopPlayback() {
        playerNode.stop()
        streamingFormat = nil
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // MARK: - Buffer Processing

    private var processBufferCallCount = 0

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        processBufferCallCount += 1
        if processBufferCallCount == 1 {
            print("[AudioService] processInputBuffer: FIRST call — frames=\(buffer.frameLength), hasConverter=\(audioConverter != nil), hasCallback=\(onAudioChunk != nil)")
        }

        let samples: [Float]

        if let converter = audioConverter {
            samples = resample(buffer: buffer, converter: converter)
        } else {
            // Already 16kHz mono — extract Float32 samples directly
            samples = extractFloat32Samples(from: buffer)
        }

        guard !samples.isEmpty else {
            if processBufferCallCount <= 3 {
                print("[AudioService] processInputBuffer: EMPTY samples (call #\(processBufferCallCount))")
            }
            return
        }

        if processBufferCallCount == 1 {
            print("[AudioService] processInputBuffer: delivering \(samples.count) samples to callback")
        }

        // Compute RMS audio level (0.0–1.0) for orb visual feedback
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        let normalized = min(1.0, rms / 0.15)
        onAudioLevel?(normalized)

        onAudioChunk?(samples)
    }

    private func resample(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> [Float] {
        let ratio = targetSampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return [] }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return [] }

        var error: NSError?
        var hasData = true
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if error != nil {
            return []
        }

        return extractFloat32Samples(from: outputBuffer)
    }

    private func extractFloat32Samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    static func makeSessionStrategy(for mode: PipelineMode, hasBluetoothInput: Bool) -> SessionStrategy {
        switch mode {
        case .local:
            // Local ASR handles its own processing; session-level voiceChat provides AEC.
            return SessionStrategy(
                sessionMode: .voiceChat,
                categoryOptions: [.allowBluetooth, .defaultToSpeaker],
                engineVoiceProcessingEnabled: false
            )
        case .live, .liveText:
            // Bluetooth HFP provides its own echo cancellation in the codec.
            // Built-in mic + speaker needs VoiceProcessingIO for hardware AEC
            // so Gemini doesn't hear its own output and self-interrupt.
            return SessionStrategy(
                sessionMode: hasBluetoothInput ? .default : .voiceChat,
                categoryOptions: [.allowBluetooth, .defaultToSpeaker],
                engineVoiceProcessingEnabled: !hasBluetoothInput
            )
        }
    }

    static func hasBluetoothInput(in route: AVAudioSessionRouteDescription) -> Bool {
        route.inputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
        }
    }
}
