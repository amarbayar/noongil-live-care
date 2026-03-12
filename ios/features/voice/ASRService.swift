import Foundation

/// Wraps sherpa-onnx ASR for both Mongolian (Delden online zipformer) and English (Moonshine offline).
final class ASRService {
    private var onlineRecognizer: SherpaOnnxRecognizer?
    private var offlineRecognizer: SherpaOnnxOfflineRecognizer?
    private var currentLanguage: Language = .mongolian

    /// Confidence threshold below which ASR output should trigger intent recovery (A-03).
    /// Set based on the user's speech accommodation level.
    private(set) var confidenceThreshold: Float = 0.6

    init() {}

    /// Initialize ASR for the given language with optional accommodation level.
    /// - Mongolian: online streaming zipformer transducer (Delden)
    /// - English: offline Moonshine Tiny int8
    func initialize(language: Language, accommodation: SpeechAccommodationLevel = .none) throws {
        // Clear previous recognizers
        onlineRecognizer = nil
        offlineRecognizer = nil
        currentLanguage = language

        let config = SpeechAccommodationConfig.config(for: accommodation)
        confidenceThreshold = config.confidenceThreshold

        switch language {
        case .mongolian:
            try initializeDelden()
        case .english:
            try initializeMoonshine()
        }
    }

    /// Legacy initializer — defaults to Mongolian.
    func initialize() throws {
        try initialize(language: .mongolian)
    }

    // MARK: - Delden (Mongolian, Online)

    private func initializeDelden() throws {
        let encoderPath = Config.asrEncoderPath
        let decoderPath = Config.asrDecoderPath
        let joinerPath = Config.asrJoinerPath
        let tokensPath = Config.asrTokensPath

        guard !encoderPath.isEmpty, !decoderPath.isEmpty,
              !joinerPath.isEmpty, !tokensPath.isEmpty else {
            throw ASRError.modelNotFound("Delden ASR model files not found. Need: encoder.int8.onnx, decoder.onnx, joiner.int8.onnx, tokens.txt")
        }

        let transducerConfig = sherpaOnnxOnlineTransducerModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            joiner: joinerPath
        )

        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokensPath,
            transducer: transducerConfig,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            modelType: "zipformer2"
        )

        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: Config.asrSampleRate,
            featureDim: 80
        )

        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            enableEndpoint: false,
            decodingMethod: "greedy_search"
        )

        onlineRecognizer = SherpaOnnxRecognizer(config: &config)
    }

    // MARK: - Moonshine (English, Offline)

    private func initializeMoonshine() throws {
        let preprocessorPath = Config.moonshinePreprocessorPath
        let encoderPath = Config.moonshineEncoderPath
        let uncachedDecoderPath = Config.moonshineUncachedDecoderPath
        let cachedDecoderPath = Config.moonshineCachedDecoderPath
        let tokensPath = Config.moonshineTokensPath

        guard !preprocessorPath.isEmpty, !encoderPath.isEmpty,
              !uncachedDecoderPath.isEmpty, !cachedDecoderPath.isEmpty,
              !tokensPath.isEmpty else {
            throw ASRError.modelNotFound("Moonshine ASR model files not found. Need: preprocess.onnx, encode.int8.onnx, uncached_decode.int8.onnx, cached_decode.int8.onnx, tokens.txt in models/moonshine/")
        }

        let moonshineConfig = sherpaOnnxOfflineMoonshineModelConfig(
            preprocessor: preprocessorPath,
            encoder: encoderPath,
            uncachedDecoder: uncachedDecoderPath,
            cachedDecoder: cachedDecoderPath
        )

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensPath,
            numThreads: 2,
            debug: 0,
            moonshine: moonshineConfig
        )

        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: Config.asrSampleRate,
            featureDim: 80
        )

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            decodingMethod: "greedy_search"
        )

        offlineRecognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    // MARK: - Recognition

    /// Recognize speech from a complete Float32 audio segment at 16kHz.
    /// Dispatches to the appropriate recognizer based on current language.
    func recognize(samples: [Float]) -> String {
        guard !samples.isEmpty else { return "" }

        switch currentLanguage {
        case .mongolian:
            return recognizeOnline(samples: samples)
        case .english:
            return recognizeOffline(samples: samples)
        }
    }

    private func recognizeOnline(samples: [Float]) -> String {
        guard let onlineRecognizer else { return "" }

        onlineRecognizer.reset()
        onlineRecognizer.acceptWaveform(samples: samples, sampleRate: Config.asrSampleRate)
        onlineRecognizer.inputFinished()

        while onlineRecognizer.isReady() {
            onlineRecognizer.decode()
        }

        let result = onlineRecognizer.getResult()
        return decodeBBPE(text: result.text, tokens: result.tokens)
    }

    private func recognizeOffline(samples: [Float]) -> String {
        guard let offlineRecognizer else { return "" }

        let result = offlineRecognizer.decode(samples: samples, sampleRate: Config.asrSampleRate)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reconstruct properly-spaced text from Delden BBPE output.
    ///
    /// sherpa-onnx decodes byte-level BPE tokens into UTF-8 text but strips the
    /// ▁ (U+2581) word boundary markers without inserting spaces. The raw tokens
    /// still retain the ▁ prefix. We use the token list to figure out where each
    /// token's bytes fall in result.text and insert spaces at word boundaries.
    ///
    /// Each non-▁ character in a token maps to exactly 1 byte in result.text
    /// (byte-fallback encoding). A bare ▁ token produces a literal space byte.
    private func decodeBBPE(text: String, tokens: [String]) -> String {
        guard !tokens.isEmpty else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let wb: Character = "\u{2581}"
        let textBytes = Array(text.utf8)
        var resultBytes: [UInt8] = []
        var bytePos = 0

        for (i, token) in tokens.enumerated() {
            let hasWB = token.first == wb
            let clean = hasWB ? String(token.dropFirst()) : token

            // Bare ▁ token produced a literal space byte in result.text
            let isBareWB = hasWB && clean.isEmpty
            let nBytes = isBareWB ? 1 : clean.count

            // Insert space at word boundary (skip first token)
            if hasWB && i > 0 && !isBareWB {
                resultBytes.append(0x20)
            }

            // Copy this token's bytes from the original decoded text
            let end = min(bytePos + nBytes, textBytes.count)
            if bytePos < end {
                resultBytes.append(contentsOf: textBytes[bytePos..<end])
            }
            bytePos = end
        }

        return (String(bytes: resultBytes, encoding: .utf8) ?? text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum ASRError: LocalizedError {
        case modelNotFound(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let detail):
                return detail
            }
        }
    }
}
