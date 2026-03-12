import Foundation

/// Lightweight wrapper around SherpaOnnx GTCRN speech denoiser.
/// Removes background noise from speech segments before ASR.
final class DenoiserService {
    private var denoiser: SherpaOnnxOfflineSpeechDenoiserWrapper?

    enum DenoiserError: LocalizedError {
        case modelNotFound
        case initializationFailed

        var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "Denoiser model not found at expected path."
            case .initializationFailed:
                return "Failed to initialize GTCRN denoiser."
            }
        }
    }

    func initialize() throws {
        let modelPath = Config.denoiserModelPath
        guard !modelPath.isEmpty else {
            throw DenoiserError.modelNotFound
        }

        let gtcrnConfig = sherpaOnnxOfflineSpeechDenoiserGtcrnModelConfig(model: modelPath)
        let modelConfig = sherpaOnnxOfflineSpeechDenoiserModelConfig(gtcrn: gtcrnConfig, numThreads: 1)
        var config = sherpaOnnxOfflineSpeechDenoiserConfig(model: modelConfig)

        let wrapper = SherpaOnnxOfflineSpeechDenoiserWrapper(config: &config)
        guard wrapper.impl != nil else {
            throw DenoiserError.initializationFailed
        }

        denoiser = wrapper
    }

    /// Denoise audio samples at 16kHz. Returns denoised samples, or original if denoiser unavailable.
    func denoise(samples: [Float]) -> [Float] {
        guard let denoiser else { return samples }
        let result = denoiser.run(samples: samples, sampleRate: Config.asrSampleRate)
        let denoised = result.samples
        return denoised.isEmpty ? samples : denoised
    }
}
