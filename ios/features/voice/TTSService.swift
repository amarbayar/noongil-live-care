import Foundation

/// Wraps sherpa-onnx offline TTS for both Mongolian (Tsetsen Piper/VITS) and English (Kokoro).
final class TTSService {
    /// Audio output from TTS generation
    struct TTSAudio {
        let samples: [Float]
        let sampleRate: Int
    }

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var currentLanguage: Language = .mongolian

    init() {}

    /// Initialize TTS for the given language.
    /// - Mongolian: Tsetsen VITS/Piper with espeak-ng
    /// - English: Kokoro Multi-lang v1.0
    func initialize(language: Language) throws {
        tts = nil
        currentLanguage = language

        switch language {
        case .mongolian:
            try initializeTsetsen()
        case .english:
            try initializeKokoro()
        }
    }

    /// Legacy initializer — defaults to Mongolian.
    func initialize() throws {
        try initialize(language: .mongolian)
    }

    // MARK: - Tsetsen (Mongolian, VITS/Piper)

    private func initializeTsetsen() throws {
        let modelPath = Config.ttsModelPath
        guard !modelPath.isEmpty else {
            throw TTSError.configError("Tsetsen TTS model not found. Need: tsetsen.onnx")
        }

        let tokensPath = Config.ttsTokensPath
        guard !tokensPath.isEmpty else {
            throw TTSError.configError("TTS tokens not found. Need: tsetsen-tokens.txt")
        }

        let dataDir = Config.ttsDataDir
        guard !dataDir.isEmpty else {
            throw TTSError.configError("espeak-ng-data directory not found.")
        }

        print("[TTS] Tsetsen model: \(modelPath)")

        let vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath,
            lexicon: "",
            tokens: tokensPath,
            dataDir: dataDir,
            noiseScale: 0.667,
            noiseScaleW: 0.8,
            lengthScale: 1.0,
            dictDir: ""
        )

        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            vits: vitsConfig,
            numThreads: 2,
            debug: 1,
            provider: "cpu"
        )

        var ttsConfig = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )

        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        guard wrapper.tts != nil else {
            throw TTSError.initializationFailed
        }
        tts = wrapper
        print("[TTS] Tsetsen initialized successfully")
    }

    // MARK: - Kokoro (English)

    private func initializeKokoro() throws {
        let modelPath = Config.kokoroModelPath
        guard !modelPath.isEmpty else {
            throw TTSError.configError("Kokoro TTS model not found. Need: model.onnx in models/kokoro/")
        }

        let voicesPath = Config.kokoroVoicesPath
        guard !voicesPath.isEmpty else {
            throw TTSError.configError("Kokoro voices not found. Need: voices.bin in models/kokoro/")
        }

        let tokensPath = Config.kokoroTokensPath
        guard !tokensPath.isEmpty else {
            throw TTSError.configError("Kokoro tokens not found. Need: tokens.txt in models/kokoro/")
        }

        let dataDir = Config.kokoroDataDir
        guard !dataDir.isEmpty else {
            throw TTSError.configError("espeak-ng-data directory not found.")
        }

        let lexiconPath = Config.kokoroLexiconPath

        print("[TTS] Kokoro model: \(modelPath)")

        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            dataDir: dataDir,
            lengthScale: 1.0,
            dictDir: "",
            lexicon: lexiconPath
        )

        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
            numThreads: 2,
            debug: 1,
            provider: "cpu"
        )

        var ttsConfig = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )

        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        guard wrapper.tts != nil else {
            throw TTSError.initializationFailed
        }
        tts = wrapper
        print("[TTS] Kokoro initialized successfully")
    }

    // MARK: - Synthesis

    /// Generate speech audio from text.
    func synthesize(text: String, speakerId: Int = 0, speed: Float = 1.0) -> TTSAudio? {
        guard let tts, !text.isEmpty else { return nil }

        let audio = tts.generate(text: text, sid: speakerId, speed: speed)
        let samples = audio.samples

        guard !samples.isEmpty else { return nil }

        return TTSAudio(
            samples: samples,
            sampleRate: Int(audio.sampleRate)
        )
    }

    enum TTSError: LocalizedError {
        case configError(String)
        case initializationFailed

        var errorDescription: String? {
            switch self {
            case .configError(let detail):
                return detail
            case .initializationFailed:
                return "TTS engine failed to initialize. Check model files are valid."
            }
        }
    }
}
