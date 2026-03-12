import Foundation
import Accelerate

/// Orchestrates all audio enhancement strategies: denoising (GTCRN) and
/// Spectral Band Replication (SBR) for extending 8kHz narrowband audio
/// into the 4-8kHz range expected by 16kHz ASR models.
final class AudioEnhancerService {
    private let denoiserService = DenoiserService()
    private(set) var isDenoiserReady = false

    // MARK: - SBR Constants

    private let fftSize = 1024
    private let hopSize = 512
    private let sampleRate: Float = 16_000

    // Pre-computed Hann window
    private lazy var hannWindow: [Float] = {
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return window
    }()

    // FFT setup (reused across calls)
    private lazy var fftSetup: FFTSetup? = {
        vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
    }()

    // MARK: - Initialization

    func initialize() throws {
        try denoiserService.initialize()
        isDenoiserReady = true
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - Enhancement Pipeline

    func enhance(samples: [Float], mode: AudioEnhancementMode) -> [Float] {
        switch mode {
        case .none:
            return samples
        case .denoiseOnly:
            return denoise(samples)
        case .sbrOnly:
            return sbr(samples)
        case .sbrThenDenoise:
            return denoise(sbr(samples))
        case .denoiseThenSbr:
            return sbr(denoise(samples))
        }
    }

    // MARK: - Denoise

    private func denoise(_ samples: [Float]) -> [Float] {
        denoiserService.denoise(samples: samples)
    }

    // MARK: - Spectral Band Replication (SBR)

    /// Extends narrowband 8kHz audio (resampled to 16kHz) by replicating the
    /// 2-4kHz band into 4-8kHz with attenuation and spectral tilt.
    ///
    /// Algorithm:
    /// - Overlap-add STFT (1024-point FFT, 512 hop, Hann window)
    /// - Copy bins 128-255 (2-4kHz) into bins 256-511 (4-8kHz) at -6dB
    /// - Apply spectral tilt rolloff (-3dB/kHz above 4kHz) for natural sound
    /// - Inverse FFT + overlap-add reconstruction
    private func sbr(_ samples: [Float]) -> [Float] {
        guard let setup = fftSetup, samples.count > fftSize else { return samples }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        let halfN = fftSize / 2

        // Source bins: 2-4kHz = bins 128..255 at 16kHz/1024
        let srcStart = 128
        let srcEnd = 255
        let srcCount = srcEnd - srcStart + 1 // 128 bins

        // Destination bins: 4-8kHz = bins 256..511
        let dstStart = 256

        // Pre-compute attenuation factors per destination bin:
        // Base -6dB + spectral tilt of -3dB per kHz above 4kHz
        let baseGain: Float = 0.5 // -6dB
        let hzPerBin = sampleRate / Float(fftSize) // 15.625 Hz/bin
        var dstGains = [Float](repeating: 0, count: srcCount)
        for i in 0..<srcCount {
            let binIndex = dstStart + i
            let freqHz = Float(binIndex) * hzPerBin
            let khzAbove4 = (freqHz - 4000.0) / 1000.0
            // -3dB/kHz = multiply by 10^(-3/20) per kHz ≈ 0.708/kHz
            let tiltGain = powf(0.708, max(khzAbove4, 0))
            dstGains[i] = baseGain * tiltGain
        }

        // Output buffer (same length as input)
        let totalSamples = samples.count
        var output = [Float](repeating: 0, count: totalSamples)

        // Temp buffers for FFT
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var windowedFrame = [Float](repeating: 0, count: fftSize)

        // Process overlapping frames
        var frameStart = 0
        while frameStart + fftSize <= totalSamples {
            // Extract and window the frame
            for i in 0..<fftSize {
                windowedFrame[i] = samples[frameStart + i] * hannWindow[i]
            }

            // Pack into split complex for vDSP
            realPart = [Float](repeating: 0, count: halfN)
            imagPart = [Float](repeating: 0, count: halfN)

            windowedFrame.withUnsafeBufferPointer { framePtr in
                framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                    var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                }
            }

            // Forward FFT
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
            vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

            // Copy source bins (2-4kHz) into destination bins (4-8kHz) with attenuation
            for i in 0..<srcCount {
                let si = srcStart + i
                let di = dstStart + i
                guard di < halfN else { break }
                realPart[di] = realPart[si] * dstGains[i]
                imagPart[di] = imagPart[si] * dstGains[i]
            }

            // Inverse FFT
            vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))

            // Unpack from split complex
            var reconstructed = [Float](repeating: 0, count: fftSize)
            reconstructed.withUnsafeMutableBufferPointer { outPtr in
                outPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                    var split = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                    vDSP_ztoc(&split, 1, complexPtr, 2, vDSP_Length(halfN))
                }
            }

            // Normalize by FFT size (vDSP convention: forward+inverse scales by N/2)
            var scale = 1.0 / Float(fftSize / 2)
            vDSP_vsmul(reconstructed, 1, &scale, &reconstructed, 1, vDSP_Length(fftSize))

            // Overlap-add into output
            for i in 0..<fftSize {
                let outIdx = frameStart + i
                if outIdx < totalSamples {
                    output[outIdx] += reconstructed[i]
                }
            }

            frameStart += hopSize
        }

        // Copy any remaining samples that didn't fit a full frame
        if frameStart < totalSamples {
            for i in frameStart..<totalSamples {
                output[i] += samples[i]
            }
        }

        return output
    }
}
