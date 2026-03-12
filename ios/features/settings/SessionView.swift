import SwiftUI
import MWDATCore
import MWDATCamera

/// Active session screen: camera preview, pipeline state, transcript, and controls.
struct SessionView: View {
    @EnvironmentObject var glassesService: GlassesService
    @EnvironmentObject var voicePipeline: VoicePipeline
    @EnvironmentObject var featureFlags: FeatureFlagService
    @EnvironmentObject var checkInCoordinator: CheckInCoordinator
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var storageService: StorageService
    @StateObject private var cameraService = CameraService()

    @State private var isSessionActive = false
    #if DEBUG
    @State private var seedStatus: String?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Bar
            HStack {
                Text("Session")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                // Clear conversation
                if !voicePipeline.conversation.isEmpty {
                    Button {
                        voicePipeline.clearConversation()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundColor(theme.textSecondary)
                            .padding(8)
                            .background(theme.surface)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // MARK: - Camera Preview
            cameraPreview
                .frame(height: 160)
                .cornerRadius(16)
                .padding(.horizontal)

            // MARK: - Debug Data Tools
            #if DEBUG
            debugDataButtons
                .padding(.horizontal)
                .padding(.top, 8)
            #endif

            // MARK: - Pipeline Status
            pipelineStatusBar
                .padding(.horizontal)
                .padding(.top, 10)

            // MARK: - Conversation Transcript
            conversationList
                .frame(maxHeight: .infinity)

            // MARK: - Controls
            controlBar
        }
        .screenBackground()
    }

    // MARK: - Camera Preview

    private var cameraPreview: some View {
        ZStack {
            Color.black

            if let frame = cameraService.latestFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: cameraService.errorMessage != nil ? "exclamationmark.triangle" : "video.slash")
                        .font(.title2)
                        .foregroundColor(cameraService.errorMessage != nil ? .red.opacity(0.6) : .gray.opacity(0.6))
                    Text(cameraService.errorMessage ?? cameraStatusText)
                        .font(.caption)
                        .foregroundColor(cameraService.errorMessage != nil ? .red.opacity(0.8) : .gray.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            // Stream state badge
            VStack {
                HStack {
                    Spacer()
                    Text(streamStateText.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .padding(8)
                }
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Pipeline Status

    private var pipelineStatusBar: some View {
        HStack(spacing: 10) {
            // State indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(pipelineStateColor)
                    .frame(width: 8, height: 8)
                Text(voicePipeline.state.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(pipelineStateColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pipelineStateColor.opacity(0.1))
            .cornerRadius(20)

            Spacer()

            // Audio indicators
            HStack(spacing: 8) {
                if voicePipeline.isMicActive {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                }

                if voicePipeline.isSpeakerActive {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if voicePipeline.conversation.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.3))
                            Text("Start speaking to begin")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }

                    ForEach(voicePipeline.conversation) { entry in
                        ConversationBubble(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: voicePipeline.conversation.count) { _ in
                if let lastID = voicePipeline.conversation.last?.id {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 0) {
            Divider()

            // Check-in state indicator
            if checkInCoordinator.isCheckInActive {
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.primary)
                        .frame(width: 8, height: 8)
                    Text("Check-in active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(theme.primary)
                    Spacer()
                    Button {
                        Task { await checkInCoordinator.cancelCheckIn() }
                    } label: {
                        Text("Cancel")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(theme.primary.opacity(0.05))
            }

            HStack(spacing: 12) {
                Spacer()

                // Check-in button (local mode only, session active, flag enabled, no active check-in)
                if canShowCheckIn {
                    Button {
                        startCheckIn()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.text.clipboard")
                                .font(.subheadline)
                            Text("Check In")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(theme.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(theme.secondary.opacity(0.1))
                        .cornerRadius(28)
                    }
                }

                Button {
                    toggleSession()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSessionActive ? "stop.fill" : "play.fill")
                            .font(.subheadline)
                        Text(isSessionActive ? "Stop Session" : "Start Session")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(isSessionActive ? theme.error : theme.primary)
                    .cornerRadius(28)
                }
                .disabled(!canStartSession && !isSessionActive)
                .opacity((!canStartSession && !isSessionActive) ? 0.5 : 1.0)
                Spacer()
            }
            .padding(.vertical, 12)
            .background(theme.surface)
        }
    }

    // MARK: - Debug Data

    #if DEBUG
    private var debugDataButtons: some View {
        HStack(spacing: 10) {
            Button {
                guard let uid = authService.currentUser?.uid else { return }
                seedStatus = "Seeding..."
                Task {
                    await CompanionHomeView.clearCheckIns(userId: uid, storage: storageService)
                    await CompanionHomeView.seedDemoData(userId: uid, storage: storageService)
                    seedStatus = "Done — switch to Home"
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                    Text("Seed Demo Data")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(theme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.primary.opacity(0.1))
                .cornerRadius(8)
            }

            Button {
                guard let uid = authService.currentUser?.uid else { return }
                seedStatus = "Clearing..."
                Task {
                    await CompanionHomeView.clearCheckIns(userId: uid, storage: storageService)
                    seedStatus = "Cleared"
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.caption)
                    Text("Clear Check-ins")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(theme.error)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.error.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()

            if let status = seedStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundColor(theme.textSecondary)
            }
        }
    }
    #endif

    // MARK: - Actions

    private func toggleSession() {
        if isSessionActive {
            stopSession()
        } else {
            startSession()
        }
    }

    private func startSession() {
        Task {
            do {
                // 1. Start voice pipeline (configures HFP audio)
                try voicePipeline.start()
                isSessionActive = true

                // 2. Wait 2s for HFP to stabilize before starting camera
                try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)

                // 3. Start camera stream (non-fatal if it fails — voice still works)
                voicePipeline.cameraService = cameraService
                await cameraService.startStream()

                // Camera errors surface via cameraService.errorMessage (shown in preview)
            } catch {
                print("[SessionView] startSession failed: \(error)")
                voicePipeline.stop()
                isSessionActive = false
            }
        }
    }

    private func stopSession() {
        Task {
            voicePipeline.stop()
            await cameraService.stopStream()
            isSessionActive = false
        }
    }

    private func startCheckIn() {
        Task {
            guard let greeting = await checkInCoordinator.beginCheckIn(type: .adhoc) else { return }
            voicePipeline.speakText(greeting)
        }
    }

    // MARK: - Computed Properties

    private var canShowCheckIn: Bool {
        isSessionActive
            && voicePipeline.pipelineMode == .local
            && featureFlags.checkInEnabled
            && !checkInCoordinator.isCheckInActive
    }

    private var canStartSession: Bool {
        let modelsReady: Bool
        switch voicePipeline.pipelineMode {
        case .local:    modelsReady = voicePipeline.isInitialized
        case .live:     modelsReady = true  // No local models needed
        case .liveText: modelsReady = voicePipeline.ttsReady  // Needs TTS only
        }
        return modelsReady && glassesService.hasConnectedDevice
    }

    private var streamStateText: String {
        switch cameraService.streamState {
        case .stopped: return "Off"
        case .waitingForDevice: return "Waiting"
        case .starting: return "Starting"
        case .streaming: return "Live"
        case .paused: return "Paused"
        case .stopping: return "Stopping"
        @unknown default: return "Unknown"
        }
    }

    private var cameraStatusText: String {
        switch cameraService.streamState {
        case .stopped: return "Camera not started"
        case .waitingForDevice: return "Waiting for glasses..."
        case .starting: return "Starting camera..."
        case .streaming: return "Streaming"
        case .paused: return "Stream paused"
        case .stopping: return "Stopping..."
        @unknown default: return ""
        }
    }

    private var streamStateBadgeColor: Color {
        switch cameraService.streamState {
        case .streaming: return .green
        case .starting, .waitingForDevice: return .orange
        case .paused: return .yellow
        case .stopped, .stopping: return .gray
        @unknown default: return .gray
        }
    }

    private var pipelineStateColor: Color {
        switch voicePipeline.state {
        case .idle: return .gray
        case .listening: return .green
        case .processing: return .orange
        case .speaking: return .blue
        }
    }
}

// MARK: - Conversation Bubble

struct ConversationBubble: View {
    let entry: VoicePipeline.ConversationEntry
    @EnvironmentObject var theme: ThemeService

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 50) }

            Text(entry.text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundColor(bubbleForeground)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if entry.role == .assistant { Spacer(minLength: 50) }
        }
    }

    private var bubbleForeground: Color {
        entry.role == .user ? .white : theme.text
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if entry.role == .user {
            LinearGradient(
                colors: [theme.primary, theme.secondary],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            theme.surface
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.text.opacity(0.08), lineWidth: 1)
                )
        }
    }
}
