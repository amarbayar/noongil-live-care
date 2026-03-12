import SwiftUI
import AVKit
import AVFoundation
import os.log

private let logger = Logger(subsystem: "ai.noongil.app", category: "CreativeCanvas")

/// Slide-up overlay for creative media generation, showing progress/skeleton during generation
/// and the finished result when ready. Designed to coexist with a docked orb below.
struct CreativeCanvasOverlay: View {
    @EnvironmentObject var theme: ThemeService

    let canvasState: CreativeCanvasState
    let onDismiss: () -> Void
    let onShare: () -> Void

    @State private var player: AVPlayer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isAudioPlaying: Bool = false
    @State private var isLooping: Bool = false
    @State private var loopObserver: NSObjectProtocol?

    private var isReadyMusic: Bool {
        canvasState.status == .ready && canvasState.result?.resolvedMediaType == .music
    }

    var body: some View {
        VStack(spacing: 0) {
            if !canvasState.isFullscreen {
                dragHandle
                    .padding(.top, 10)
            }

            // Music player has its own title/subtitle — skip redundant header
            if !isReadyMusic && !canvasState.isFullscreen {
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            mediaOrSkeleton
                .padding(.horizontal, canvasState.isFullscreen ? 0 : 20)
                .padding(.top, canvasState.isFullscreen ? 0 : (isReadyMusic ? 8 : 16))

            if canvasState.status == .ready, canvasState.result != nil, !isReadyMusic, !canvasState.isFullscreen {
                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer(minLength: canvasState.isFullscreen ? 0 : 12)
        }
        .padding(.bottom, canvasState.isFullscreen ? 0 : 8)
        .background(canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: canvasState.isFullscreen ? 0 : 28, style: .continuous))
        .shadow(color: .black.opacity(canvasState.isFullscreen ? 0 : 0.35), radius: 24, y: -4)
        .onAppear { configurePlayback() }
        .onDisappear { removeRouteObserver(); removeLoopObserver(); stopPlayback() }
        .onChange(of: canvasState.result) { _ in configurePlayback() }
        .task(id: canvasState.playbackToken) { configurePlayback() }
        .task(id: canvasState.mediaActionToken) { executeMediaAction() }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .frame(width: 40, height: 5)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                mediaTypeIcon
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))

                Text(canvasState.title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Close canvas")
            }

            Text(canvasState.subtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)

            if canvasState.status == .generating || canvasState.status == .streaming {
                progressSection
            }
        }
    }

    private var mediaTypeIcon: some View {
        Group {
            switch canvasState.mediaType {
            case .image:
                Image(systemName: "photo.artframe")
            case .video:
                Image(systemName: "film")
            case .music:
                Image(systemName: "music.note")
            case .animation:
                Image(systemName: "sparkles.rectangle.stack")
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            if let progress = canvasState.progressFraction {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white.opacity(0.9))
            } else {
                ProgressView()
                    .tint(.white.opacity(0.9))
            }
        }
    }

    // MARK: - Media or Skeleton

    @ViewBuilder
    private var mediaOrSkeleton: some View {
        switch canvasState.status {
        case .clarifying, .generating:
            skeletonPlaceholder
        case .streaming:
            streamingMusicPlayer
        case .ready:
            if let result = canvasState.result {
                readyMedia(result)
            } else {
                skeletonPlaceholder
            }
        case .failed:
            failedContent
        case .cancelled:
            cancelledContent
        }
    }

    private var skeletonPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .aspectRatio(skeletonAspectRatio, contentMode: .fit)
            .overlay(skeletonOverlay)
            .shimmer()
    }

    private var skeletonAspectRatio: CGFloat {
        switch canvasState.mediaType {
        case .image: return 1.0
        case .video, .animation: return 16.0 / 9.0
        case .music: return 2.5
        }
    }

    @ViewBuilder
    private var skeletonOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: skeletonIcon)
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))

            if let detail = canvasState.progressDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    private var skeletonIcon: String {
        switch canvasState.mediaType {
        case .image: return "photo.artframe"
        case .video: return "film"
        case .music: return "waveform"
        case .animation: return "sparkles.rectangle.stack"
        }
    }

    @ViewBuilder
    private func readyMedia(_ result: CreativeResult) -> some View {
        switch result.resolvedMediaType {
        case .image:
            if let image = result.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(canvasState.imageRotationDegrees))
                    .scaleEffect(canvasState.imageZoomScale)
                    .animation(.easeInOut(duration: 0.3), value: canvasState.imageRotationDegrees)
                    .animation(.easeInOut(duration: 0.3), value: canvasState.imageZoomScale)
                    .cornerRadius(canvasState.isFullscreen ? 0 : 16)
            }

        case .video, .animation:
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .cornerRadius(canvasState.isFullscreen ? 0 : 16)
            } else if let image = result.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(canvasState.isFullscreen ? 0 : 16)
            }

        case .music:
            musicPlayer(result)
        }
    }

    // MARK: - Music Player

    private func musicPlayer(_ result: CreativeResult) -> some View {
        VStack(spacing: 16) {
            // Dismiss button row
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Close")
            }

            // Waveform visualizer
            waveformVisualizer
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Title — the generation prompt
            Text(canvasState.prompt)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Progress bar with time labels
            musicProgressBar

            // Transport controls
            musicTransportControls
        }
        .padding(.vertical, 8)
    }

    private var waveformVisualizer: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.white.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(waveformBars)
    }

    private var waveformBars: some View {
        let barDurations: [Double] = [0.4, 0.55, 0.7, 0.5, 0.65]
        let barHeights: [CGFloat] = [0.4, 0.7, 1.0, 0.6, 0.8]
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        return HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                WaveformBar(
                    isAnimating: isAudioPlaying && !reduceMotion,
                    baseHeight: barHeights[index],
                    duration: barDurations[index]
                )
            }
        }
        .padding(.horizontal, 60)
    }

    private var musicProgressBar: some View {
        VStack(spacing: 4) {
            TimelineView(.animation(minimumInterval: 0.5)) { _ in
                GeometryReader { geo in
                    let dur = audioPlayer?.duration ?? 0
                    let progress = dur > 0 ? (audioPlayer?.currentTime ?? 0) / dur : 0

                    ZStack(alignment: .leading) {
                        // Track background
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 4)

                        // Fill
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 4)

                        // Knob
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, geo.size.width * CGFloat(progress) - 6))
                    }
                }
                .frame(height: 12)
            }

            TimelineView(.animation(minimumInterval: 0.5)) { _ in
                HStack {
                    Text(formatTime(audioPlayer?.currentTime ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    Text(formatTime(audioPlayer?.duration ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private var musicTransportControls: some View {
        HStack(spacing: 40) {
            Button {
                seekPlayer(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(minWidth: 48, minHeight: 48)
            }
            .accessibilityLabel("Skip back 10 seconds")

            Button {
                toggleAudioPlayback()
            } label: {
                Image(systemName: isAudioPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .accessibilityLabel(isAudioPlaying ? "Pause" : "Play")

            Button {
                seekPlayer(by: 10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(minWidth: 48, minHeight: 48)
            }
            .accessibilityLabel("Skip forward 10 seconds")
        }
    }

    private func toggleAudioPlayback() {
        guard audioPlayer != nil else { return }
        if isAudioPlaying {
            audioPlayer?.pause()
            isAudioPlaying = false
        } else {
            audioPlayer?.play()
            isAudioPlaying = true
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    // MARK: - Streaming Music Player

    private var streamingMusicPlayer: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Close")
            }

            // Waveform visualizer
            waveformVisualizer
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(canvasState.prompt)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Streaming")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            if let detail = canvasState.progressDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 8)
    }

    private var failedContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange.opacity(0.9))

            Text(canvasState.statusMessage.isEmpty
                ? "Something went wrong. Try again by asking Mira."
                : canvasState.statusMessage)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(20)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    private var cancelledContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "stop.circle")
                .font(.title2)
                .foregroundColor(.white.opacity(0.5))

            Text("Generation was stopped.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(20)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 48)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white.opacity(0.9))
                    .cornerRadius(14)
            }
            .accessibilityLabel("Share creation")

            Button(action: onDismiss) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 48)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.22))
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Background

    private var canvasBackground: some View {
        RoundedRectangle(cornerRadius: canvasState.isFullscreen ? 0 : 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: canvasState.isFullscreen ? 0 : 28, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: canvasState.isFullscreen ? 0 : 28, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: canvasState.isFullscreen ? 0 : 1)
            )
    }

    // MARK: - Playback

    private func configurePlayback() {
        stopPlayback()

        guard let result = canvasState.result, canvasState.status == .ready else {
            logger.info("configurePlayback: no result or not ready (status=\(canvasState.status.rawValue))")
            return
        }

        logger.info("configurePlayback: mediaType=\(result.resolvedMediaType.rawValue), hasAudio=\(result.audioData != nil), audioBytes=\(result.audioData?.count ?? 0)")

        if let videoURL = result.playbackVideoURL {
            player = AVPlayer(url: videoURL)
            player?.actionAtItemEnd = .pause
            player?.play()
            setupLoopObserverIfNeeded()
        }

        if result.resolvedMediaType == .music || result.shouldPlaySeparateAudioTrack {
            startAudioPlayback(result)
        }
    }

    @State private var routeChangeObserver: NSObjectProtocol?
    @State private var pendingAudioData: Data?

    private func startAudioPlayback(_ result: CreativeResult) {
        guard let audioData = result.audioData else { return }

        // Voice pipeline uses .playAndRecord + .allowBluetooth which locks BT to HFP.
        // Switch to .playAndRecord + .allowBluetoothA2DP (without .allowBluetooth):
        //   Output → Bluetooth A2DP (stereo, high quality music)
        //   Input  → built-in iPhone mic (keeps Mira listening)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            logger.error("Audio session config failed: \(error)")
        }

        let session = AVAudioSession.sharedInstance()
        let currentOutput = session.currentRoute.outputs.first?.portType

        if currentOutput != .bluetoothHFP {
            // Already on A2DP, speaker, or wired — play immediately
            beginPlayback(data: audioData)
        } else {
            // Still on HFP — wait for Bluetooth stack to negotiate A2DP
            pendingAudioData = audioData
            waitForRouteChange()
        }
    }

    private func waitForRouteChange() {
        removeRouteObserver()

        // Timeout: play anyway after 3s even if route didn't switch
        let timeout = DispatchWorkItem { [self] in
            removeRouteObserver()
            if let data = pendingAudioData {
                pendingAudioData = nil
                logger.info("Route change timeout — playing on current route")
                beginPlayback(data: data)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timeout)

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            let output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType
            logger.info("Route changed to: \(output?.rawValue ?? "none")")

            if output != .bluetoothHFP {
                timeout.cancel()
                removeRouteObserver()
                if let data = pendingAudioData {
                    pendingAudioData = nil
                    beginPlayback(data: data)
                }
            }
        }
    }

    private func removeRouteObserver() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    private func beginPlayback(data: Data) {
        do {
            let ap = try AVAudioPlayer(data: data)
            ap.volume = 1.0
            ap.numberOfLoops = isLooping ? -1 : 0
            ap.prepareToPlay()
            let ok = ap.play()
            audioPlayer = ap
            isAudioPlaying = ok
            let route = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "?"
            logger.info("Audio playing: duration=\(ap.duration)s started=\(ok) route=\(route)")
        } catch {
            logger.error("AVAudioPlayer failed: \(error)")
        }
    }

    private func executeMediaAction() {
        guard let action = canvasState.pendingMediaAction else { return }

        logger.info("executeMediaAction: \(String(describing: action)), hasPlayer=\(player != nil), hasAudio=\(audioPlayer != nil)")

        switch action {
        case .play:
            ensurePlayerReady()
            player?.play()
            audioPlayer?.play()
            if audioPlayer != nil { isAudioPlaying = true }
        case .pause:
            player?.pause()
            audioPlayer?.pause()
            isAudioPlaying = false
        case .replay:
            ensurePlayerReady()
            if let player {
                player.seek(to: .zero) { [weak player] finished in
                    logger.info("replay seek finished=\(finished)")
                    player?.play()
                }
            }
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
            if audioPlayer != nil { isAudioPlaying = true }
        case .seekForward:
            seekPlayer(by: 10)
        case .seekBackward:
            seekPlayer(by: -10)
        case .stop:
            stopPlayback()
        case .volumeUp:
            adjustVolume(by: 0.2)
        case .volumeDown:
            adjustVolume(by: -0.2)
        case .mute:
            player?.isMuted.toggle()
            if let ap = audioPlayer { ap.volume = ap.volume > 0 ? 0 : 1.0 }
        case .speed(let value):
            if let player, player.timeControlStatus == .playing { player.rate = Float(value) }
        case .loop:
            isLooping.toggle()
            audioPlayer?.numberOfLoops = isLooping ? -1 : 0
            setupLoopObserverIfNeeded()
        case .save:
            saveToPhotos()
        case .rotateLeft, .rotateRight, .zoomIn, .zoomOut, .zoomReset,
             .fullscreen, .exitFullscreen, .next, .previous, .delete:
            break // Handled by manager state — no player interaction
        }
    }

    /// Re-create the player if it was nil'd (e.g., after stopPlayback) but result still has media.
    private func ensurePlayerReady() {
        if player == nil, let videoURL = canvasState.result?.playbackVideoURL {
            logger.info("ensurePlayerReady: re-creating AVPlayer for \(videoURL.lastPathComponent)")
            player = AVPlayer(url: videoURL)
            setupLoopObserverIfNeeded()
        }
        if audioPlayer == nil, let audioData = canvasState.result?.audioData,
           canvasState.result?.resolvedMediaType == .music {
            do {
                let ap = try AVAudioPlayer(data: audioData)
                ap.volume = 1.0
                ap.numberOfLoops = isLooping ? -1 : 0
                ap.prepareToPlay()
                audioPlayer = ap
            } catch {
                logger.error("ensurePlayerReady: AVAudioPlayer failed: \(error)")
            }
        }
    }

    private func seekPlayer(by seconds: Double) {
        if let player {
            let current = player.currentTime()
            let target = CMTimeAdd(current, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
            player.seek(to: target)
        }
        if let audioPlayer {
            audioPlayer.currentTime = max(0, audioPlayer.currentTime + seconds)
        }
    }

    private func adjustVolume(by delta: Float) {
        if let player {
            player.volume = min(1.0, max(0.0, player.volume + delta))
        }
        if let audioPlayer {
            audioPlayer.volume = min(1.0, max(0.0, audioPlayer.volume + delta))
        }
    }

    private func stopPlayback() {
        removeLoopObserver()
        player?.pause()
        player = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isAudioPlaying = false
    }

    // MARK: - Loop Observer

    private func setupLoopObserverIfNeeded() {
        removeLoopObserver()
        guard isLooping, let item = player?.currentItem else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [self] _ in
            if isLooping {
                player?.seek(to: .zero)
                player?.play()
            }
        }
    }

    private func removeLoopObserver() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }

    // MARK: - Save to Photos

    private func saveToPhotos() {
        guard let result = canvasState.result else { return }
        switch result.resolvedMediaType {
        case .image:
            if let image = result.image {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                logger.info("saveToPhotos: image saved")
            }
        case .video, .animation:
            if let videoURL = result.playbackVideoURL {
                UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
                logger.info("saveToPhotos: video saved")
            }
        case .music:
            // Music files don't save to Photos — use share sheet instead
            logger.info("saveToPhotos: music not supported, use share")
        }
    }
}

// MARK: - Waveform Bar

private struct WaveformBar: View {
    let isAnimating: Bool
    let baseHeight: CGFloat
    let duration: Double

    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white.opacity(0.8))
            .frame(width: 8, height: animating ? 80 * baseHeight : 20)
            .onChange(of: isAnimating) { active in
                if active {
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                        animating = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animating = false
                    }
                }
            }
            .onAppear {
                if isAnimating {
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                        animating = true
                    }
                }
            }
    }
}
