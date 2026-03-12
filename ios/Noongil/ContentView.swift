import SwiftUI
import AuthenticationServices

/// Main tab view switching between Setup and Session screens.
/// Shows sign-in screen when not authenticated.
struct ContentView: View {
    @EnvironmentObject var glassesService: GlassesService
    @EnvironmentObject var voicePipeline: VoicePipeline
    @EnvironmentObject var featureFlags: FeatureFlagService
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var consentService: ConsentService

    @StateObject private var checkInCoordinator = CheckInCoordinator(
        checkInService: CheckInService(provider: GeminiCompanionAdapter(), userId: "")
    )
    @StateObject private var medicationService = MedicationService(userId: "")
    @StateObject private var reportFlowCoordinator = ReportFlowCoordinator()
    @StateObject private var checkInScheduleService = CheckInScheduleService()
    @StateObject private var customReminderService = CustomReminderService()
    @StateObject private var voiceMessageInboxService = VoiceMessageInboxService()

    @State private var selectedTab: DockTab = .home

    var body: some View {
        Group {
            if authService.isAuthenticated {
                if consentService.allConsentsGranted {
                    mainContent
                } else {
                    PrivacyConsentView()
                }
            } else {
                signInView
            }
        }
    }

    // MARK: - Visible Tabs

    private var visibleTabs: [DockTab] {
        var tabs: [DockTab] = [.home, .journal]
        if featureFlags.medicationRemindersEnabled {
            tabs.append(.reminders)
        }
        if authService.currentUser?.uid != nil {
            tabs.append(.caregivers)
        }
        tabs.append(.setup)
        #if DEBUG
        tabs.append(.session)
        #endif
        return tabs
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            selectedView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if voicePipeline.creativeCanvas?.isFullscreen != true {
                FloatingDockView(selectedTab: $selectedTab, visibleTabs: visibleTabs)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }
        }
        .environmentObject(checkInCoordinator)
        .environmentObject(medicationService)
        .environmentObject(reportFlowCoordinator)
        .environmentObject(checkInScheduleService)
        .environmentObject(customReminderService)
        .environmentObject(voiceMessageInboxService)
        .onAppear {
            glassesService.startObserving()
            voicePipeline.configure(with: featureFlags)
            voicePipeline.initializeModels()
            setupCheckInCoordinator()
            setupMedicationService()
            setupReportCoordinator()
        }
        .onChange(of: checkInScheduleService.pendingCheckIn) { pending in
            if pending {
                selectedTab = .home
            }
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selectedTab {
        case .home:
            CompanionHomeView()
        case .journal:
            HealthHistoryView()
        case .reminders:
            RemindersView()
        case .caregivers:
            if let uid = authService.currentUser?.uid {
                CaregiverLinkView(userId: uid, storageService: storageService)
            }
        case .setup:
            SetupView()
        #if DEBUG
        case .session:
            SessionView()
        #endif
        }
    }

    private func setupCheckInCoordinator() {
        guard let uid = authService.currentUser?.uid else { return }
        let provider = GeminiCompanionAdapter(geminiService: voicePipeline.geminiService)
        let liveSessionStore = FirestoreLiveCheckInSessionStore(storageService: storageService)
        let graphSync = GraphSyncService(
            sessionStore: liveSessionStore,
            userId: uid
        )
        let memoryProjection = MemoryProjectionService(
            sessionStore: liveSessionStore,
            storageService: storageService,
            geminiService: voicePipeline.geminiService,
            userId: uid
        )
        let service = CheckInService(
            provider: provider,
            storageService: storageService,
            graphSyncService: graphSync,
            userId: uid
        )
        checkInCoordinator.checkInService = service
        voicePipeline.checkInCoordinator = checkInCoordinator
        voicePipeline.userId = uid
        voicePipeline.storageService = storageService
        voicePipeline.graphSyncService = graphSync
        voicePipeline.memoryProjectionService = memoryProjection
        voicePipeline.consentService = consentService
        voicePipeline.creativeAuthTokenProvider = { [weak authService] in
            try await authService?.currentUser?.getIDToken()
        }

        Task {
            await graphSync.drainPendingGraphSyncs()
            await memoryProjection.drainPendingMemoryProjections()
        }

        // Wire check-in schedule service
        checkInScheduleService.configure(
            notificationService: notificationService,
            storageService: storageService,
            userId: uid
        )
        AppDelegate.checkInScheduleService = checkInScheduleService

        // Pick up buffered notification that arrived before wiring
        checkInScheduleService.drainPendingNotification()

        Task {
            await checkInScheduleService.loadSchedule()
            let name = authService.currentUser?.displayName?.components(separatedBy: " ").first ?? ""
            await checkInScheduleService.scheduleCheckInNotifications(userName: name)
        }
    }

    private func setupMedicationService() {
        guard let uid = authService.currentUser?.uid else { return }

        // Configure the @StateObject with real dependencies
        medicationService.configure(
            userId: uid,
            storageService: storageService,
            notificationService: notificationService
        )

        // Wire the reminder handler to the SAME instance the UI uses
        let handler = MedicationReminderHandler(
            medicationService: medicationService,
            notificationService: notificationService
        )
        AppDelegate.reminderHandler = handler

        // Configure custom reminder service
        customReminderService.configure(
            userId: uid,
            storageService: storageService,
            notificationService: notificationService
        )

        voiceMessageInboxService.configure(
            userId: uid,
            storageService: storageService,
            notificationService: notificationService
        )

        // Fetch and reschedule
        Task {
            await medicationService.fetchMedications()
            await medicationService.rescheduleAllReminders()
            await customReminderService.fetchReminders()
            await customReminderService.rescheduleAllNotifications()
            await voiceMessageInboxService.fetchMessages()
        }
    }

    private func setupReportCoordinator() {
        voicePipeline.reportFlowCoordinator = reportFlowCoordinator
    }

    // MARK: - Sign In

    private var signInView: some View {
        SignInScreen(authService: authService, theme: theme)
    }
}

// MARK: - Sign In Screen

private struct SignInScreen: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var theme: ThemeService

    @State private var appeared = false
    @State private var ringScale1: CGFloat = 0.85
    @State private var ringScale2: CGFloat = 0.9
    @State private var ringRotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Decorative floating rings
            decorativeRings

            VStack(spacing: 0) {
                Spacer()

                // Orb + branding
                VStack(spacing: 20) {
                    OrbView(state: .resting, size: 120)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.8)

                    VStack(spacing: 6) {
                        Text("Noongil")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)

                        Text("Your voice health companion")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                    }
                }

                Spacer()
                    .frame(height: 48)

                // Feature highlights
                VStack(spacing: 14) {
                    featureRow(icon: "waveform", text: "Daily check-ins through natural conversation", index: 0)
                    featureRow(icon: "heart.text.clipboard", text: "Track mood, sleep, and symptoms effortlessly", index: 1)
                    featureRow(icon: "person.2", text: "Keep caregivers informed with shared insights", index: 2)
                }
                .padding(.horizontal, 40)

                Spacer()

                // Sign in button + status
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        let appleRequest = authService.createAppleIDRequest()
                        request.requestedScopes = appleRequest.requestedScopes
                        request.nonce = appleRequest.nonce
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            Task {
                                await authService.handleAppleSignIn(authorization)
                            }
                        case .failure(let error):
                            print("[ContentView] Sign in with Apple failed: \(error)")
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.horizontal, 48)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
                    }

                    if let error = authService.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
                    .frame(height: 48)
            }
        }
        .screenBackground()
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                ringScale1 = 1.05
                ringScale2 = 1.1
            }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    // MARK: - Decorative Rings

    private var decorativeRings: some View {
        ZStack {
            // Large outer ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 320, height: 320)
                .scaleEffect(ringScale1)
                .rotationEffect(.degrees(ringRotation))

            // Inner ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.06), .white.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .frame(width: 240, height: 240)
                .scaleEffect(ringScale2)
                .rotationEffect(.degrees(-ringRotation * 0.7))

            // Dot accents on the rings
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 6, height: 6)
                .offset(x: 150, y: -30)
                .rotationEffect(.degrees(ringRotation * 0.5))

            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 4, height: 4)
                .offset(x: -110, y: 80)
                .rotationEffect(.degrees(-ringRotation * 0.3))
        }
        .offset(y: -60)
    }

    // MARK: - Feature Row

    private func featureRow(icon: String, text: String, index: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.1))
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .staggeredAppear(index: index, delay: 0.15)
    }
}
