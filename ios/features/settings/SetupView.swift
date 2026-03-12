import SwiftUI
import MWDATCore

/// Setup screen: glasses registration, device connection status, permissions, and model status.
struct SetupView: View {
    @EnvironmentObject var glassesService: GlassesService
    @EnvironmentObject var voicePipeline: VoicePipeline
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var consentService: ConsentService

    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showingLegalDocument: PrivacyConsentView.LegalDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Noongil")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Setup & Configuration")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // MARK: - Pipeline Mode
                pipelineModeCard

                // MARK: - Language Picker
                languageCard

                // MARK: - Connection Card
                connectionCard

                // MARK: - Models Card (hidden in Live mode — no local ASR/TTS)
                if voicePipeline.pipelineMode != .live {
                    modelsCard
                }

                // MARK: - Audio Enhancement Card
                audioEnhancementCard

                // MARK: - Voice Settings Card
                voiceSettingsCard

                // MARK: - Config Card
                configCard

                // MARK: - Legal
                legalCard

                // MARK: - Account
                accountCard

                // MARK: - Errors
                if glassesService.configureError != nil || glassesService.errorMessage != nil {
                    errorsCard
                }
            }
            .padding(.bottom, 16)
        }
        .screenBackground()
        .sheet(item: $showingLegalDocument) { doc in
            LegalDocumentView(document: doc)
                .environmentObject(theme)
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .task {
            await glassesService.checkCameraPermission()
        }
    }

    // MARK: - Pipeline Mode

    private var pipelineModeCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Pipeline Mode", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
            }

            Picker("Mode", selection: $voicePipeline.pipelineMode) {
                ForEach(PipelineMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: pipelineModeIcon)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                Text(pipelineModeDescription)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }

            if voicePipeline.pipelineMode == .live || voicePipeline.pipelineMode == .liveText {
                Divider()

                if voicePipeline.pipelineMode == .live {
                    HStack {
                        Text("Gemini Voice")
                            .font(.subheadline)
                            .foregroundColor(theme.text)
                        Spacer()
                        Picker("Voice", selection: $voicePipeline.liveVoiceId) {
                            ForEach(Config.liveVoices) { voice in
                                Text(voice.label).tag(voice.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.primary)
                    }
                }

                HStack {
                    Text("Connection")
                        .font(.subheadline)
                        .foregroundColor(theme.text)
                    Spacer()
                    statusPill(
                        text: liveConnectionText,
                        color: liveConnectionColor
                    )
                }

                if voicePipeline.pipelineMode == .liveText {
                    HStack {
                        Text("TTS")
                            .font(.subheadline)
                            .foregroundColor(theme.text)
                        Spacer()
                        statusPill(
                            text: voicePipeline.ttsReady ? "Ready" : "Not Ready",
                            color: voicePipeline.ttsReady ? theme.success : theme.error
                        )
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Language

    private var languageCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Language", systemImage: "globe")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
                if voicePipeline.pipelineMode == .live {
                    Text("Auto-detect")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }

            if voicePipeline.pipelineMode == .local || voicePipeline.pipelineMode == .liveText {
                Picker("Language", selection: Binding(
                    get: { voicePipeline.language },
                    set: { voicePipeline.switchLanguage($0) }
                )) {
                    ForEach(Language.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)

                if voicePipeline.pipelineMode == .liveText {
                    Text("Gemini listens in any language; TTS speaks in selected language")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Gemini Live auto-detects language from speech (70+ languages)")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
    }

    // MARK: - Connection

    private var connectionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
                statusPill(text: registrationText, color: registrationColor)
            }

            Divider()

            if glassesService.connectedDeviceIds.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "eyeglasses")
                        .font(.title2)
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(theme.surface)
                        .cornerRadius(10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Glasses Connected")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(theme.text)
                        Text("Tap below to pair your Ray-Ban Meta")
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                    }
                    Spacer()
                }
            } else {
                ForEach(glassesService.connectedDeviceIds, id: \.self) { deviceId in
                    let device = Wearables.shared.deviceForIdentifier(deviceId)
                    HStack(spacing: 12) {
                        Image(systemName: "eyeglasses")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(theme.success)
                            .cornerRadius(10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device?.name ?? deviceId)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(theme.text)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(theme.success)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(theme.success)
                    }
                }
            }

            if !glassesService.isRegistered {
                Button {
                    glassesService.startRegistration()
                } label: {
                    Label("Connect Glasses", systemImage: "link")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.primary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            } else {
                Button {
                    glassesService.startUnregistration()
                } label: {
                    Label("Disconnect", systemImage: "link.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.surface)
                        .foregroundColor(theme.error)
                        .cornerRadius(12)
                }
            }

            if glassesService.isRegistered {
                Divider()
                HStack {
                    Text("Camera Access")
                        .font(.subheadline)
                        .foregroundColor(theme.text)
                    Spacer()
                    if glassesService.cameraPermission == .granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(theme.success)
                    } else {
                        Button {
                            Task {
                                await glassesService.requestCameraPermission()
                            }
                        } label: {
                            Label("Grant Camera Access", systemImage: "camera")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(theme.warning)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Models

    private var modelsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("ML Models", systemImage: "cpu")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
                if voicePipeline.isInitialized {
                    statusPill(text: "Ready", color: theme.success)
                } else if voicePipeline.initError != nil {
                    statusPill(text: "Error", color: theme.error)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.primary)
                }
            }

            if let error = voicePipeline.initError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(theme.error.opacity(0.08))
                    .cornerRadius(8)
            }

            Divider()

            VStack(spacing: 8) {
                if voicePipeline.pipelineMode == .local {
                    if voicePipeline.language == .mongolian {
                        modelRow("ASR Encoder (Delden)", icon: "waveform", path: Config.asrEncoderPath)
                        modelRow("ASR Decoder (Delden)", icon: "waveform", path: Config.asrDecoderPath)
                        modelRow("ASR Joiner (Delden)", icon: "waveform", path: Config.asrJoinerPath)
                        modelRow("ASR Tokens", icon: "doc.text", path: Config.asrTokensPath)
                        modelRow("TTS Model (Tsetsen)", icon: "speaker.wave.2", path: Config.ttsModelPath)
                    } else {
                        modelRow("ASR Preprocessor (Moonshine)", icon: "waveform", path: Config.moonshinePreprocessorPath)
                        modelRow("ASR Encoder (Moonshine)", icon: "waveform", path: Config.moonshineEncoderPath)
                        modelRow("ASR Uncached Dec (Moonshine)", icon: "waveform", path: Config.moonshineUncachedDecoderPath)
                        modelRow("ASR Cached Dec (Moonshine)", icon: "waveform", path: Config.moonshineCachedDecoderPath)
                        modelRow("ASR Tokens (Moonshine)", icon: "doc.text", path: Config.moonshineTokensPath)
                        modelRow("TTS Model (Kokoro)", icon: "speaker.wave.2", path: Config.kokoroModelPath)
                        modelRow("TTS Voices (Kokoro)", icon: "speaker.wave.2", path: Config.kokoroVoicesPath)
                    }
                } else {
                    // liveText mode: only TTS models needed (ASR is server-side)
                    if voicePipeline.language == .mongolian {
                        modelRow("TTS Model (Tsetsen)", icon: "speaker.wave.2", path: Config.ttsModelPath)
                    } else {
                        modelRow("TTS Model (Kokoro)", icon: "speaker.wave.2", path: Config.kokoroModelPath)
                        modelRow("TTS Voices (Kokoro)", icon: "speaker.wave.2", path: Config.kokoroVoicesPath)
                    }
                }
                modelRow("VAD Model", icon: "mic.badge.plus", path: Config.vadModelPath)
                modelRow("Denoiser (GTCRN)", icon: "waveform.badge.minus", path: Config.denoiserModelPath)
            }

            if !voicePipeline.isInitialized {
                Button {
                    voicePipeline.initializeModels()
                } label: {
                    Label("Retry Initialization", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.warning)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Audio Enhancement

    private var audioEnhancementCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Audio Enhancement", systemImage: "speaker.wave.3")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
            }

            Divider()

            HStack {
                Text("Input Sample Rate")
                    .font(.subheadline)
                    .foregroundColor(theme.text)
                Spacer()
                let rate = voicePipeline.audioService.inputSampleRate
                if rate > 0 {
                    Text("\(Int(rate)) Hz")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(rate >= 16_000 ? theme.success : theme.error)
                    if rate < 16_000 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(theme.warning)
                    }
                } else {
                    Text("--")
                        .font(.subheadline)
                        .foregroundColor(theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Enhancement Mode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(theme.text)
                Picker("Enhancement", selection: $voicePipeline.enhancementMode) {
                    ForEach(AudioEnhancementMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.minus")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 20)
                Text("Denoiser (GTCRN)")
                    .font(.subheadline)
                    .foregroundColor(theme.text)
                Spacer()
                Image(systemName: voicePipeline.denoiserReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(voicePipeline.denoiserReady ? theme.success : theme.error.opacity(0.7))
            }
            .padding(.vertical, 2)

            HStack(spacing: 10) {
                Image(systemName: "waveform.path")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 20)
                Text("SBR (DSP)")
                    .font(.subheadline)
                    .foregroundColor(theme.text)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(theme.success)
            }
            .padding(.vertical, 2)
        }
        .glassCard()
    }

    // MARK: - Voice Settings

    private var voiceSettingsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Voice Settings", systemImage: "person.wave.2")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
            }

            Divider()

            HStack {
                Text("Speaker")
                    .font(.subheadline)
                    .foregroundColor(theme.text)
                Spacer()
                Picker("Speaker", selection: $voicePipeline.speakerId) {
                    ForEach(currentSpeakers) { speaker in
                        Text(speaker.name).tag(speaker.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.primary)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Speed")
                        .font(.subheadline)
                        .foregroundColor(theme.text)
                    Spacer()
                    Text(String(format: "%.1fx", voicePipeline.ttsSpeed))
                        .font(.subheadline)
                        .foregroundColor(theme.textSecondary)
                }
                Slider(value: $voicePipeline.ttsSpeed, in: 0.5...2.0, step: 0.1)
                    .tint(theme.primary)
            }
        }
        .glassCard()
    }

    // MARK: - Config

    private var configCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Configuration", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
            }

            Divider()

            configRow("Gemini Model", value: Config.geminiModel)
            configRow("API Key",
                      value: Config.geminiAPIKey.isEmpty ? "Not Set" : "Configured",
                      valueColor: Config.geminiAPIKey.isEmpty ? theme.error : theme.success)
            configRow("ASR Sample Rate", value: "\(Config.asrSampleRate) Hz")
        }
        .glassCard()
    }

    // MARK: - Errors

    private var errorsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Errors", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(theme.error)
                Spacer()
            }
            if let configErr = glassesService.configureError {
                Text(configErr)
                    .font(.caption)
                    .foregroundColor(theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(theme.error.opacity(0.08))
                    .cornerRadius(6)
            }
            if let error = glassesService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(theme.error.opacity(0.08))
                    .cornerRadius(6)
            }
        }
        .glassCard()
    }

    // MARK: - Legal

    private var legalCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Legal", systemImage: "doc.text")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
            }

            Divider()

            Button {
                showingLegalDocument = .privacyPolicy
            } label: {
                HStack {
                    Image(systemName: "hand.raised")
                        .font(.subheadline)
                        .frame(width: 24)
                    Text("Privacy Policy")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
                .foregroundColor(theme.text)
                .padding(.vertical, 4)
            }

            Button {
                showingLegalDocument = .termsOfService
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext")
                        .font(.subheadline)
                        .frame(width: 24)
                    Text("Terms of Service")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
                .foregroundColor(theme.text)
                .padding(.vertical, 4)
            }

            Button {
                showingLegalDocument = .accessibilityStatement
            } label: {
                HStack {
                    Image(systemName: "accessibility")
                        .font(.subheadline)
                        .frame(width: 24)
                    Text("Accessibility")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
                .foregroundColor(theme.text)
                .padding(.vertical, 4)
            }

            Divider()

            Button {
                consentService.revokeAll()
            } label: {
                Label("Reset Consent", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.warning.opacity(0.15))
                    .foregroundColor(theme.warning)
                    .cornerRadius(12)
            }
        }
        .glassCard()
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Account", systemImage: "person.crop.circle")
                    .font(.headline)
                    .foregroundColor(theme.text)
                Spacer()
            }

            Divider()

            Button {
                isExporting = true
                Task {
                    await exportData()
                    isExporting = false
                }
            } label: {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Label("Export My Data", systemImage: "arrow.down.doc")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.primary.opacity(0.1))
                        .foregroundColor(theme.primary)
                        .cornerRadius(12)
                }
            }
            .disabled(isExporting)

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.error.opacity(0.1))
                    .foregroundColor(theme.error)
                    .cornerRadius(12)
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await authService.deleteAccount(consentService: consentService)
                    }
                }
            } message: {
                Text("This will permanently delete all your data including check-ins, health records, and account information. This cannot be undone.")
            }
        }
        .glassCard()
    }

    private func exportData() async {
        guard let user = authService.currentUser else { return }
        do {
            let token = try await user.getIDToken()
            let url = URL(string: "\(Config.backendBaseURL)/api/users/me/export")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("noongil-export.json")
            try data.write(to: tempURL)
            exportURL = tempURL
        } catch {
            print("[SetupView] Export failed: \(error)")
        }
    }

    // MARK: - Components

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(20)
    }

    @ViewBuilder
    private func modelRow(_ name: String, icon: String, path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .frame(width: 20)
            Text(name)
                .font(.subheadline)
                .foregroundColor(theme.text)
            Spacer()
            Image(systemName: path.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(path.isEmpty ? theme.error.opacity(0.7) : theme.success)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func configRow(_ label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(theme.text)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor ?? theme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var currentSpeakers: [Config.TTSSpeaker] {
        voicePipeline.language == .mongolian ? Config.tsetsenSpeakers : Config.kokoroSpeakers
    }

    private var registrationText: String {
        switch glassesService.registrationState {
        case .registered:
            return "Connected"
        case .unavailable:
            return "Unavailable"
        case .available:
            return "Ready"
        case .registering:
            return "Connecting..."
        @unknown default:
            return "Unknown"
        }
    }

    private var registrationColor: Color {
        switch glassesService.registrationState {
        case .registered:
            return theme.success
        case .unavailable:
            return theme.error
        case .available:
            return theme.textSecondary
        case .registering:
            return theme.warning
        @unknown default:
            return theme.textSecondary
        }
    }

    private var pipelineModeIcon: String {
        switch voicePipeline.pipelineMode {
        case .local: return "cpu"
        case .live: return "bolt.fill"
        case .liveText: return "bolt.horizontal.fill"
        }
    }

    private var pipelineModeDescription: String {
        switch voicePipeline.pipelineMode {
        case .local: return "On-device VAD + ASR + TTS via Gemini REST"
        case .live: return "Gemini Live WebSocket — native audio, ~500ms latency"
        case .liveText: return "Gemini Live (listening) + on-device TTS (speaking)"
        }
    }

    private var liveConnectionText: String {
        switch voicePipeline.liveConnectionState {
        case .disconnected: return "Start session to connect"
        case .connecting: return "Connecting..."
        case .settingUp: return "Setting up..."
        case .ready: return "Connected"
        case .error(let msg): return "Error: \(msg.prefix(40))"
        }
    }

    private var liveConnectionColor: Color {
        switch voicePipeline.liveConnectionState {
        case .disconnected: return theme.textSecondary
        case .connecting, .settingUp: return theme.warning
        case .ready: return theme.success
        case .error: return theme.error
        }
    }
}
