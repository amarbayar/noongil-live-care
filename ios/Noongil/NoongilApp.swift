import SwiftUI
import MWDATCore
import FirebaseCore
import UserNotifications

@main
struct NoongilApp: App {
    @StateObject private var glassesService = GlassesService()
    @StateObject private var voicePipeline = VoicePipeline()
    @StateObject private var featureFlags = FeatureFlagService()
    @StateObject private var theme = ThemeService()
    @StateObject private var strings = StringsService()
    @StateObject private var authService = AuthService()
    @StateObject private var storageService = StorageService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var consentService = ConsentService()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        FirebaseApp.configure()
        print("[Noongil] Firebase configured")

        do {
            try Wearables.configure()
            print("[Noongil] Wearables.configure() succeeded")
            if let mwdat = Bundle.main.infoDictionary?["MWDAT"] as? [String: Any] {
                print("[Noongil] MWDAT config: \(mwdat)")
            } else {
                print("[Noongil] WARNING: No MWDAT dictionary in Info.plist!")
            }
        } catch {
            print("[Noongil] Wearables.configure() failed: \(error)")
            DispatchQueue.main.async { [glassesService] in
                glassesService.configureError = "MWDAT configure failed: \(error)"
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(glassesService)
                .environmentObject(voicePipeline)
                .environmentObject(featureFlags)
                .environmentObject(theme)
                .environmentObject(strings)
                .environmentObject(authService)
                .environmentObject(storageService)
                .environmentObject(notificationService)
                .environmentObject(consentService)
                .onOpenURL { url in
                    Task {
                        await glassesService.handleUrl(url)
                    }
                }
                .task {
                    notificationService.registerCategories()
                }
        }
    }
}

// MARK: - AppDelegate (Notification Delegate)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Holds a reference to the reminder handler once wired by ContentView.
    static var reminderHandler: MedicationReminderHandler?

    /// Holds a reference to the check-in schedule service for notification routing.
    static var checkInScheduleService: CheckInScheduleService?


    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when a notification action is tapped while app is in foreground or background.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        Task { @MainActor in
            let type = userInfo["type"] as? String ?? ""

            if type.hasPrefix("checkin_") {
                // Check-in notification — set both: service (if wired) and buffer (if not)
                CheckInScheduleService.pendingCheckInFromNotification = true
                AppDelegate.checkInScheduleService?.pendingCheckIn = true
            } else if type.hasPrefix("custom_reminder") {
                // Custom reminder — just open the app (no special action needed)
            } else {
                // Medication reminder
                await AppDelegate.reminderHandler?.handleNotificationResponse(
                    actionIdentifier: actionId,
                    userInfo: userInfo
                )
            }
        }

        completionHandler()
    }

    // Show notifications even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
