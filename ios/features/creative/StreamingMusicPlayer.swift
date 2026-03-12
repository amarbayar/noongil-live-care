import AVFoundation

/// Plays continuous PCM audio chunks from Lyria RealTime using AVAudioEngine.
/// Format: 44.1kHz, stereo, 16-bit PCM (Int16 LE from API → Float32 for AVAudioEngine).
///
/// Does NOT configure the audio session — the voice pipeline owns it.
/// AVAudioEngine plays through whatever session is already active.
final class StreamingMusicPlayer {
    enum State: Equatable {
        case idle
        case buffering
        case playing
        case paused
        case stopped
    }

    private(set) var state: State = .idle
    var onStateChanged: ((State) -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var bufferedChunkCount = 0
    private var totalChunksReceived = 0
    private let prefillChunkCount = 3

    init() {
        // 44.1kHz stereo Float32 — AVAudioEngine's native working format
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Config.lyriaRealtimeSampleRate),
            channels: 2,
            interleaved: false
        )!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Public

    func enqueueChunk(_ pcmData: Data) {
        guard state != .stopped else { return }

        totalChunksReceived += 1
        if totalChunksReceived <= 5 || totalChunksReceived % 50 == 0 {
            print("[StreamingMusicPlayer] Chunk #\(totalChunksReceived): \(pcmData.count) bytes, state=\(state)")
        }

        guard let buffer = int16ToFloat32Buffer(pcmData) else {
            print("[StreamingMusicPlayer] Failed to convert chunk #\(totalChunksReceived) (\(pcmData.count) bytes)")
            return
        }

        playerNode.scheduleBuffer(buffer)
        bufferedChunkCount += 1

        if state == .idle || state == .buffering {
            updateState(.buffering)
            if bufferedChunkCount >= prefillChunkCount {
                startPlayback()
            }
        }
    }

    func play() {
        guard state == .paused else { return }
        playerNode.play()
        updateState(.playing)
    }

    func pause() {
        guard state == .playing else { return }
        playerNode.pause()
        updateState(.paused)
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        bufferedChunkCount = 0
        updateState(.stopped)
    }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = min(1.0, max(0.0, newValue)) }
    }

    // MARK: - Private

    private func startPlayback() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()
            let route = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "?"
            print("[StreamingMusicPlayer] Playback started — route=\(route), chunks=\(bufferedChunkCount)")
            updateState(.playing)
        } catch {
            print("[StreamingMusicPlayer] Engine start failed: \(error)")
            updateState(.stopped)
        }
    }

    /// Convert interleaved Int16 LE stereo PCM to non-interleaved Float32 for AVAudioEngine.
    private func int16ToFloat32Buffer(_ data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / 2  // 2 bytes per Int16 sample
        let frameCount = sampleCount / 2  // stereo: 2 samples per frame
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return nil }

        data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for frame in 0..<frameCount {
                let leftSample = Int16(littleEndian: int16Buffer[frame * 2])
                let rightSample = Int16(littleEndian: int16Buffer[frame * 2 + 1])
                leftChannel[frame] = Float(leftSample) / 32768.0
                rightChannel[frame] = Float(rightSample) / 32768.0
            }
        }

        return buffer
    }

    private func updateState(_ newState: State) {
        state = newState
        print("[StreamingMusicPlayer] state → \(newState)")
        onStateChanged?(newState)
    }
}
