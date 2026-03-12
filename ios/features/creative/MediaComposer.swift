import AVFoundation

/// Composes a video file with an audio track overlay.
struct MediaComposer {

    /// Combines a video file with audio data (WAV) into a single MP4.
    /// The audio is trimmed to match the video duration.
    static func compose(videoURL: URL, audioData: Data) async throws -> URL {
        // Write audio data to temp file
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try audioData.write(to: audioURL)

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let composition = AVMutableComposition()

        // Insert video track
        let videoDuration = try await videoAsset.load(.duration)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ComposerError.noVideoTrack
        }
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        try compositionVideoTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )

        // Insert audio track (trimmed to video duration)
        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            let audioDuration = try await audioAsset.load(.duration)
            let trimmedDuration = CMTimeMinimum(audioDuration, videoDuration)
            try compositionAudioTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: trimmedDuration),
                of: audioTrack,
                at: .zero
            )
        }

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ComposerError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw ComposerError.exportFailed
        }

        // Clean up temp audio file
        try? FileManager.default.removeItem(at: audioURL)

        return outputURL
    }

    enum ComposerError: Error, LocalizedError {
        case noVideoTrack
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "No video track found"
            case .exportFailed: return "Video export failed"
            }
        }
    }
}
