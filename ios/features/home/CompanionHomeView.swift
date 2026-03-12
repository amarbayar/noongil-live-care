import SwiftUI
import MWDATCore
import MWDATCamera

/// Companion-first home screen centered around the breathing orb.
struct CompanionHomeView: View {
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var voicePipeline: VoicePipeline
    @EnvironmentObject var glassesService: GlassesService
    @EnvironmentObject var featureFlags: FeatureFlagService
    @EnvironmentObject var checkInCoordinator: CheckInCoordinator
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var reportFlowCoordinator: ReportFlowCoordinator
    @EnvironmentObject var checkInScheduleService: CheckInScheduleService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var cameraService = CameraService()
    @StateObject private var phoneCameraService = PhoneCameraService()

    @State private var orbState: OrbState = .resting
    @State var glowDays: [GlowDay] = []
    @State var checkInProgress = CheckInProgress(completed: 0, total: 3)
    @State private var wasCheckInActive = false
    @State private var showReportShareSheet = false
    @State private var showCreativeShareSheet = false
    @State private var canvasDragOffset: CGFloat = 0
    @State private var isOrbPressed = false
    @State private var didTriggerOrbPressHaptic = false

    private var canvasLayout: CompanionHomeCanvasLayout {
        CompanionHomeCanvasLayout.make(canvas: voicePipeline.creativeCanvas)
    }

    var body: some View {
        ZStack {
            ambientBackground

            VStack(spacing: 0) {
                if voicePipeline.cameraPreviewActive {
                    Spacer(minLength: 20)
                    CameraPreviewOverlay(
                        cameraService: phoneCameraService,
                        onCapture: {
                            Task {
                                if let photo = await phoneCameraService.capturePhoto() {
                                    voicePipeline.sendCapturedPhotoToGemini(photo)
                                    let manager = voicePipeline.ensureCreativeFlowManagerForInjection()
                                    let prompt = phoneCameraService.currentPosition == .front ? "Selfie" : "Photo"
                                    manager.injectCapturedImage(photo, prompt: prompt)
                                }
                                voicePipeline.cameraPreviewActive = false
                                phoneCameraService.stop()
                            }
                        },
                        onDismiss: {
                            voicePipeline.cameraPreviewActive = false
                            phoneCameraService.stop()
                        }
                    )
                    .padding(.horizontal, 12)
                    dockedOrbSection
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                } else if canvasLayout.showsCanvasOverlay {
                    Spacer(minLength: 20)
                    canvasOverlaySection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    dockedOrbSection
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                } else {
                    mainContent
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: canvasLayout.showsCanvasOverlay)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: voicePipeline.cameraPreviewActive)
        }
        .onAppear {
            loadData()
            updateOrbState(from: voicePipeline.state)
            wasCheckInActive = checkInCoordinator.isCheckInActive
            // Deferred check for pending notification (cold start timing)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                handlePendingCheckIn()
            }
        }
        .onChange(of: voicePipeline.state) { newState in
            updateOrbState(from: newState)
        }
        .onChange(of: checkInCoordinator.isCheckInActive) { active in
            handleCheckInChange(active: active)
        }
        .onChange(of: reportFlowCoordinator.flowState) { state in
            if state == .generating { orbState = .processing }
        }
        .onChange(of: checkInScheduleService.pendingCheckIn) { _ in
            handlePendingCheckIn()
        }
        .sheet(isPresented: $showReportShareSheet) {
            if let pdfData = reportFlowCoordinator.generatedPDFData {
                ShareSheet(items: [pdfData])
            }
        }
        .sheet(isPresented: $showCreativeShareSheet) {
            if let result = voicePipeline.creativeCanvas?.result {
                ShareSheet(items: creativeShareItems(from: result))
            }
        }
    }

    // MARK: - Background

    private var ambientBackground: some View {
        homeBackgroundStyle.gradient
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.4), value: displayedOrbState)
    }

    // MARK: - Canvas Overlay (slide-up with swipe dismiss)

    private var canvasOverlaySection: some View {
        Group {
            if let canvas = voicePipeline.creativeCanvas {
                CreativeCanvasOverlay(
                    canvasState: canvas,
                    onDismiss: { dismissCreativeResult() },
                    onShare: { showCreativeShareSheet = true }
                )
                .offset(y: canvasDragOffset)
                .gesture(canvasDragGesture)
            }
        }
        .padding(.horizontal, 12)
    }

    private var canvasDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Only allow downward drag
                canvasDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                if canvasDragOffset > 120 || velocity > 300 {
                    // Dismiss with animation
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        canvasDragOffset = UIScreen.main.bounds.height
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        dismissCreativeResult()
                        canvasDragOffset = 0
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        canvasDragOffset = 0
                    }
                }
            }
    }

    // MARK: - Docked Orb (compact, below canvas)

    private var dockedOrbSection: some View {
        VStack(spacing: 6) {
            ZStack {
                HTMLOrbRendererView(state: displayedOrbState, size: 80)
                Circle()
                    .fill(Color.clear)
                    .contentShape(Circle())
                    .onTapGesture { handleOrbTap() }
                    .simultaneousGesture(orbPressGesture)
            }
            .frame(width: 88, height: 88)
            .opacity(orbTapOpacity)
            .scaleEffect(orbPressScale)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: isOrbPressed)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(orbPresentation.accessibilityLabel)

            OrbWaveformView(state: displayedOrbState)
                .frame(width: 80, height: 20)
        }
    }

    // MARK: - Main Content (centered orb layout)

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()

            greetingText
                .padding(.bottom, 32)

            orbControlSection

            if !glowDays.isEmpty {
                GlowHistoryView(days: glowDays)
                    .padding(.top, 28)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Greeting

    private var greetingText: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String = {
            if hour >= 5 && hour < 12 { return "Good morning" }
            if hour >= 12 && hour < 17 { return "Good afternoon" }
            return "Good evening"
        }()
        let name = authService.currentUser?.displayName?.components(separatedBy: " ").first ?? ""
        let fullGreeting = name.isEmpty ? greeting : "\(greeting), \(name)"

        return Text(fullGreeting)
            .font(.title2)
            .foregroundColor(homeBackgroundStyle.primaryText.color)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Orb + Ring

    private var orbControlSection: some View {
        VStack(spacing: 14) {
            ZStack {
                if shouldShowStatusRing {
                    StatusRingView(progress: checkInProgress, size: 252)
                        .transition(.opacity)
                }
                HTMLOrbRendererView(state: displayedOrbState, size: 224)
                Circle()
                    .fill(Color.clear)
                    .contentShape(Circle())
                    .onTapGesture {
                        handleOrbTap()
                    }
                    .simultaneousGesture(orbPressGesture)
            }
            .frame(width: 252, height: 252)
            .opacity(orbTapOpacity)
            .scaleEffect(orbPressScale)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: isOrbPressed)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(orbPresentation.accessibilityLabel)
            .accessibilityHint(orbPresentation.accessibilityHint)

            OrbWaveformView(state: displayedOrbState)
                .frame(width: 120, height: 36)
        }
    }

    // MARK: - State Mapping

    private func updateOrbState(from pipelineState: VoicePipeline.PipelineState) {
        let previousState = orbState
        let newState: OrbState
        switch pipelineState {
        case .idle: newState = .resting
        case .listening:
            newState = .listening
            // Nod when Mira finishes speaking → back to listening
            if previousState == .speaking {
                HapticService.speakingEnded()
            }
        case .processing:
            newState = .processing
            HapticService.speechRecognized()
        case .speaking:
            newState = .speaking
            HapticService.speakingStarted()
        }
        orbState = newState
    }

    private func handleCheckInChange(active: Bool) {
        if wasCheckInActive && !active {
            if reduceMotion {
                orbState = .resting
            } else {
                orbState = .complete
            }
            HapticService.checkInComplete()
            AudioCueService.playCheckInComplete()
            if !reduceMotion {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run { orbState = .resting }
                    loadData()
                }
            } else {
                loadData()
            }
        }
        wasCheckInActive = active
    }

    // MARK: - Actions

    private func handlePendingCheckIn() {
        guard checkInScheduleService.pendingCheckIn else {
            print("[HomeView] handlePendingCheckIn: no pending check-in")
            return
        }
        checkInScheduleService.pendingCheckIn = false
        guard !isSessionActive else {
            print("[HomeView] handlePendingCheckIn: session already active")
            return
        }
        guard canStartSession else {
            print("[HomeView] handlePendingCheckIn: cannot start session yet")
            return
        }
        print("[HomeView] handlePendingCheckIn: auto-starting session with proactive greeting")
        voicePipeline.proactiveGreeting = true
        startSession()
    }

    private func toggleSession() {
        if isSessionActive {
            stopSession()
        } else {
            startSession()
        }
    }

    private func handleOrbTap() {
        handleOrbPressChanged(false)
        guard CompanionHomeOrbChrome.isTapEnabled(
            canStartSession: canStartSession,
            isSessionActive: isSessionActive
        ) else {
            return
        }
        toggleSession()
    }

    private func handleOrbPressChanged(_ isPressed: Bool) {
        self.isOrbPressed = isPressed

        guard CompanionHomeOrbChrome.isTapEnabled(
            canStartSession: canStartSession,
            isSessionActive: isSessionActive
        ) else {
            didTriggerOrbPressHaptic = false
            return
        }

        if isPressed {
            guard !didTriggerOrbPressHaptic else { return }
            didTriggerOrbPressHaptic = true
            HapticService.orbPressed()
        } else {
            didTriggerOrbPressHaptic = false
        }
    }

    private func startSession() {
        let isLive = voicePipeline.pipelineMode == .live || voicePipeline.pipelineMode == .liveText
        let unifiedEnabled = featureFlags.unifiedGuidanceEnabled
        let checkInDue = isLive && !unifiedEnabled && featureFlags.checkInEnabled && !checkInCoordinator.isCheckInActive && checkInProgress.completed < checkInProgress.total
        print("[HomeView] startSession — unified=\(unifiedEnabled), checkInDue=\(checkInDue), mode=\(voicePipeline.pipelineMode)")
        if isLive {
            orbState = .processing
        }
        Task {
            do {
                // Enable creative + camera tools
                var extraTools: [[String: Any]] = []
                if featureFlags.creativeGenerationEnabled {
                    extraTools += CreativeFlowManager.creativeToolDeclarations
                }
                extraTools += PhoneCameraService.toolDeclarations
                voicePipeline.defaultExtraTools = extraTools

                // Always wire phone camera (not gated on glasses)
                voicePipeline.phoneCameraService = phoneCameraService

                if unifiedEnabled && isLive {
                    // Unified path: single prompt, single connection, memory-aware
                    let prepared = await voicePipeline.prepareUnifiedSession(
                        companionName: featureFlags.companionName
                    )
                    if prepared {
                        print("[HomeView] Unified session prepared")
                    } else {
                        print("[HomeView] Unified prep failed, falling back to normal session")
                    }
                } else if checkInDue {
                    // Legacy path: prepare check-in before connect
                    print("[HomeView] Preparing check-in before connect...")
                    let prepared = await voicePipeline.prepareLiveCheckIn(type: .adhoc)
                    if prepared {
                        print("[HomeView] Check-in prepared, starting pipeline (single connection)...")
                    } else {
                        print("[HomeView] Check-in prep failed, starting normal session...")
                    }
                }

                try voicePipeline.start()

                // Start camera if glasses are connected
                if glassesService.hasConnectedDevice {
                    try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                    voicePipeline.cameraService = cameraService
                    await cameraService.startStream()
                }
            } catch {
                print("[HomeView] startSession failed: \(error)")
                voicePipeline.stop()
            }
        }
    }

    private func stopSession() {
        Task {
            voicePipeline.stop()
            await cameraService.stopStream()
            phoneCameraService.stop()
            orbState = defaultIdleOrbState
        }
    }

    private func dismissCreativeResult() {
        voicePipeline.dismissCreativeCanvas()
    }

    private func creativeShareItems(from result: CreativeResult) -> [Any] {
        var items: [Any] = []
        if let image = result.image {
            items.append(image)
        }
        if let url = result.composedVideoURL ?? result.videoURL {
            items.append(url)
        }
        if let audio = result.audioData {
            // Write to temp file for share sheet
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mira-music.m4a")
            try? audio.write(to: tempURL)
            items.append(tempURL)
        }
        if items.isEmpty {
            items.append(result.prompt)
        }
        return items
    }

    // MARK: - Computed Properties

    private var canStartSession: Bool {
        switch voicePipeline.pipelineMode {
        case .local: return voicePipeline.isInitialized
        case .live: return true
        case .liveText: return voicePipeline.ttsReady
        }
    }

    private var displayedOrbState: OrbState {
        if case .error = voicePipeline.liveConnectionState {
            return .error
        }
        if isLiveSessionConnecting {
            return .processing
        }
        if voicePipeline.pipelineMode == .local, voicePipeline.initError != nil, !isSessionActive {
            return .error
        }
        if !isSessionActive {
            return defaultIdleOrbState
        }
        return orbState
    }

    private var defaultIdleOrbState: OrbState {
        let isLive = voicePipeline.pipelineMode == .live || voicePipeline.pipelineMode == .liveText
        let checkInDue = isLive
            && !featureFlags.unifiedGuidanceEnabled
            && featureFlags.checkInEnabled
            && !checkInCoordinator.isCheckInActive
            && checkInProgress.completed < checkInProgress.total

        return checkInDue ? .checkInDue : .resting
    }

    private var shouldShowStatusRing: Bool {
        CompanionHomeOrbChrome.shouldShowStatusRing(
            isSessionActive: isSessionActive,
            state: displayedOrbState
        )
    }

    private var orbTapOpacity: Double {
        CompanionHomeOrbChrome.orbOpacity(
            canStartSession: canStartSession,
            isSessionActive: isSessionActive
        )
    }

    private var orbPressScale: Double {
        CompanionHomeOrbChrome.orbScale(
            isPressed: isOrbPressed,
            canStartSession: canStartSession,
            isSessionActive: isSessionActive
        )
    }

    private var orbPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                handleOrbPressChanged(true)
            }
            .onEnded { _ in
                handleOrbPressChanged(false)
            }
    }

    private var orbPresentation: CompanionHomeOrbPresentation {
        CompanionHomeOrbPresentation.make(
            state: displayedOrbState,
            isSessionActive: isSessionActive,
            canStartSession: canStartSession,
            isConnecting: isLiveSessionConnecting
        )
    }

    private var homeBackgroundStyle: CompanionHomeBackgroundStyle {
        CompanionHomeBackgroundStyle.make(for: displayedOrbState)
    }

    private var isLiveSessionConnecting: Bool {
        guard isSessionActive else { return false }
        guard voicePipeline.pipelineMode == .live || voicePipeline.pipelineMode == .liveText else {
            return false
        }

        switch voicePipeline.liveConnectionState {
        case .connecting, .settingUp:
            return true
        case .disconnected, .ready, .error:
            return false
        }
    }

    private var isSessionActive: Bool {
        voicePipeline.hasActiveSession
    }

}
