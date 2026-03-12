import Foundation

/// Wraps sherpa-onnx Silero VAD for voice activity detection on 16kHz audio.
/// Detects speech segments and emits complete speech audio for ASR processing.
final class VADService {
    /// Called when a complete speech segment is detected (after silence).
    /// Provides Float32 samples at 16kHz.
    var onSpeechSegment: (([Float]) -> Void)?

    /// Called when speech starts (for UI feedback)
    var onSpeechStart: (() -> Void)?

    /// Called when speech ends (for UI feedback)
    var onSpeechEnd: (() -> Void)?

    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var isSpeaking = false
    private(set) var currentAccommodation: SpeechAccommodationLevel = .none

    init() {}

    /// Initialize the Silero VAD model with accommodation parameters.
    func initialize(accommodation: SpeechAccommodationLevel = .none) throws {
        let modelPath = Config.vadModelPath
        guard !modelPath.isEmpty else {
            throw VADError.modelNotFound
        }

        currentAccommodation = accommodation
        let config = SpeechAccommodationConfig.config(for: accommodation)

        var sileroConfig = sherpaOnnxSileroVadModelConfig(
            model: modelPath,
            threshold: config.vadThreshold,
            minSilenceDuration: config.minSilenceDuration,
            minSpeechDuration: config.minSpeechDuration,
            windowSize: Int(Config.vadWindowSize),
            maxSpeechDuration: config.maxSpeechDuration
        )

        var vadConfig = sherpaOnnxVadModelConfig(
            sileroVad: sileroConfig,
            sampleRate: Int32(Config.asrSampleRate),
            numThreads: 1,
            provider: "cpu",
            debug: 0
        )

        vad = SherpaOnnxVoiceActivityDetectorWrapper(
            config: &vadConfig,
            buffer_size_in_seconds: 120
        )
    }

    /// Feed 16kHz Float32 audio samples to the VAD.
    /// Must be called with chunks of exactly `Config.vadWindowSize` samples (512).
    func processAudio(_ samples: [Float]) {
        guard let vad else { return }

        // Feed samples in windowSize chunks as required by Silero VAD
        let windowSize = Config.vadWindowSize
        var offset = 0

        while offset + windowSize <= samples.count {
            let chunk = Array(samples[offset..<offset + windowSize])
            vad.acceptWaveform(samples: chunk)
            offset += windowSize

            // Check if speech detected (for UI)
            if vad.isSpeechDetected() && !isSpeaking {
                isSpeaking = true
                onSpeechStart?()
            }

            // Check for completed speech segments
            while !vad.isEmpty() {
                let segment = vad.front()
                vad.pop()

                isSpeaking = false
                onSpeechEnd?()

                let segmentSamples = segment.samples
                if !segmentSamples.isEmpty {
                    onSpeechSegment?(segmentSamples)
                }
            }
        }

        // If we were speaking and no more speech detected
        if isSpeaking && !vad.isSpeechDetected() {
            // Let it naturally finish via the segment detection above
        }
    }

    /// Reset the VAD state.
    func reset() {
        vad?.reset()
        isSpeaking = false
    }

    enum VADError: LocalizedError {
        case modelNotFound

        var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "Silero VAD model not found in bundle"
            }
        }
    }
}
