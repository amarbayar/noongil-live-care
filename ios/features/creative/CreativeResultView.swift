import SwiftUI
import AVKit
import AVFoundation

/// Full-screen sheet displaying generated creative media (image, video, music, or animation).
struct CreativeResultView: View {
    @EnvironmentObject var theme: ThemeService

    let result: CreativeResult
    let canvasState: CreativeCanvasState?
    let onDismiss: () -> Void
    let onShare: () -> Void

    @State private var player: AVPlayer?
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                if let canvasState, shouldShowStatusBanner(for: canvasState) {
                    statusBanner(for: canvasState)
                        .padding(.top, 24)
                }

                Spacer()

                mediaContent

                Spacer()

                buttonRow
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .onAppear { configurePlayback() }
        .onDisappear { stopPlayback() }
        .onChange(of: result) { _ in
            configurePlayback()
        }
    }

    // MARK: - Media Content

    @ViewBuilder
    private var mediaContent: some View {
        switch result.resolvedMediaType {
        case .image:
            if let image = result.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(radius: 8)
            } else {
                unavailableContent(message: "Image ready, but preview is unavailable.")
            }

        case .video:
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .cornerRadius(16)
            } else {
                unavailableContent(message: "Video ready, but playback is unavailable.")
            }

        case .music:
            VStack(spacing: 16) {
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(theme.primary)
                Text("Music Generated")
                    .font(.title2)
                    .foregroundColor(theme.text)
                Text(audioPlayer == nil ? "Playback unavailable" : "Playing now")
                    .font(.body)
                    .foregroundColor(theme.textSecondary)
            }

        case .animation:
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .cornerRadius(16)
            } else if let image = result.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(radius: 8)
            } else {
                unavailableContent(message: "Animation ready, but preview is unavailable.")
            }

        case .voiceMessage:
            VStack(spacing: 16) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 80))
                    .foregroundColor(theme.primary)
                Text("Voice Message")
                    .font(.title2)
                    .foregroundColor(theme.text)
            }
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack(spacing: 20) {
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(minWidth: 60, minHeight: 60)
                    .padding(.horizontal, 24)
                    .background(theme.primary.opacity(0.15))
                    .foregroundColor(theme.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel("Share creation")

            Button(action: onDismiss) {
                Text("Done")
                    .font(.headline)
                    .frame(minWidth: 60, minHeight: 60)
                    .padding(.horizontal, 24)
                    .background(theme.primary)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func statusBanner(for canvasState: CreativeCanvasState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(canvasState.title)
                .font(.headline)
                .foregroundColor(theme.text)

            Text(canvasState.subtitle)
                .font(.subheadline)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.leading)

            if canvasState.status == .generating {
                if let progress = canvasState.progressFraction {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(theme.primary)
                } else {
                    ProgressView()
                        .tint(theme.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.surface.opacity(0.96))
        .cornerRadius(20)
    }

    // MARK: - Setup

    private func configurePlayback() {
        stopPlayback()

        if let videoURL = result.playbackVideoURL {
            player = AVPlayer(url: videoURL)
            player?.play()
        }

        if result.resolvedMediaType == .music || result.shouldPlaySeparateAudioTrack {
            startAudioPlayback()
        }
    }

    private func startAudioPlayback() {
        guard let audioData = result.audioData else { return }
        do {
            let audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            self.audioPlayer = audioPlayer
        } catch {
            print("[CreativeResultView] Audio playback setup failed: \(error)")
        }
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func unavailableContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(theme.primary)
            Text(message)
                .font(.body)
                .foregroundColor(theme.text)
                .multilineTextAlignment(.center)
        }
    }

    private func shouldShowStatusBanner(for canvasState: CreativeCanvasState) -> Bool {
        canvasState.status == .generating
            || canvasState.status == .failed
            || canvasState.status == .cancelled
    }
}
