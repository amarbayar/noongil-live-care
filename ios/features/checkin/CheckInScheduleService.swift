import Foundation

/// Schedules morning/evening check-in notifications based on user's preferred times.
/// Observable so views can bind to schedule state and the app can react to pending check-ins.
@MainActor
final class CheckInScheduleService: ObservableObject {

    // MARK: - Constants

    static let nudgeDelaySeconds: TimeInterval = 10 * 60 // 10 minutes

    // MARK: - Notification Buffer (cold start)

    /// Buffer for when notification arrives before any instance is wired.
    /// AppDelegate sets this; the instance drains it in `drainPendingNotification()`.
    static var pendingCheckInFromNotification = false

    /// Call after wiring to pick up any buffered notification.
    func drainPendingNotification() {
        if Self.pendingCheckInFromNotification {
            Self.pendingCheckInFromNotification = false
            pendingCheckIn = true
        }
    }

    // MARK: - Published State

    @Published var schedule: CheckInSchedule = CheckInSchedule()
    @Published var pendingCheckIn = false

    // MARK: - Dependencies

    private var notificationService: NotificationService?
    private var storageService: StorageService?
    private var userId: String?

    // Track current IDs so we can cancel before rescheduling
    private var scheduledIds: [String] = []

    // MARK: - Init

    init() {}

    /// Configure with dependencies after auth. Same pattern as MedicationService.
    func configure(
        notificationService: NotificationService,
        storageService: StorageService,
        userId: String
    ) {
        self.notificationService = notificationService
        self.storageService = storageService
        self.userId = userId
    }

    /// Test-friendly configuration path for scheduling behavior that does not require Firestore.
    func configure(
        notificationService: NotificationService,
        userId: String
    ) {
        self.notificationService = notificationService
        self.userId = userId
    }

    // MARK: - Persistence

    /// Load the schedule from Firestore and apply it.
    func loadSchedule() async {
        guard let storage = storageService, let uid = userId else { return }

        do {
            if let saved = try await storage.fetch(
                CheckInSchedule.self,
                from: "profile",
                userId: uid,
                documentId: "checkInSchedule"
            ) {
                schedule = saved
            }
        } catch {
            print("[CheckInScheduleService] Failed to load schedule: \(error)")
        }
    }

    /// Save the current schedule to Firestore.
    func saveSchedule() async {
        guard let storage = storageService, let uid = userId else { return }

        do {
            _ = try await storage.save(
                schedule,
                to: "profile",
                userId: uid,
                documentId: "checkInSchedule"
            )
        } catch {
            print("[CheckInScheduleService] Failed to save schedule: \(error)")
        }
    }

    // MARK: - Schedule

    /// Schedules check-in notifications for the current schedule. Cancels any previous ones first.
    func scheduleCheckInNotifications(userName: String = "") async {
        guard let notificationService = notificationService else { return }

        // Cancel existing before scheduling new
        if !scheduledIds.isEmpty {
            notificationService.cancelNotifications(ids: scheduledIds)
            scheduledIds.removeAll()
        }

        if schedule.morningEnabled, let time = schedule.morningTime {
            await scheduleWindow(type: "morning", time: time, userName: userName)
        }

        if schedule.eveningEnabled, let time = schedule.eveningTime {
            await scheduleWindow(type: "evening", time: time, userName: userName)
        }
    }

    /// Cancels all scheduled check-in notifications.
    func cancelAllCheckInNotifications() {
        notificationService?.cancelNotifications(ids: scheduledIds)
        scheduledIds.removeAll()
    }

    // MARK: - Private

    private func scheduleWindow(type: String, time: String, userName: String) async {
        guard let notificationService = notificationService else { return }
        guard let components = parseTime(time) else { return }

        let mainId = "checkin_\(type)_\(time)"
        let nudgeId = "checkin_nudge_\(type)_\(time)"

        let greeting = type == "morning" ? "Good morning" : "Good evening"
        let body = userName.isEmpty
            ? "\(greeting). Ready when you are."
            : "\(greeting), \(userName). Ready when you are."

        // Main notification at scheduled time
        await notificationService.scheduleNotification(
            id: mainId,
            title: "Check-In Time",
            body: body,
            at: components,
            repeats: true,
            category: NotificationService.medicationCategoryId,
            userInfo: [
                "type": "checkin_\(type)",
                "scheduledTime": time
            ]
        )
        scheduledIds.append(mainId)

        // Nudge 10 minutes later
        var nudgeComponents = components
        let nudgeMinute = (components.minute ?? 0) + 10
        nudgeComponents.minute = nudgeMinute % 60
        if nudgeMinute >= 60 {
            nudgeComponents.hour = ((components.hour ?? 0) + 1) % 24
        }

        await notificationService.scheduleNotification(
            id: nudgeId,
            title: "Mira is waiting",
            body: "Your \(type) check-in is ready. Tap to start.",
            at: nudgeComponents,
            repeats: true,
            userInfo: [
                "type": "checkin_nudge",
                "scheduledTime": time
            ]
        )
        scheduledIds.append(nudgeId)
    }

    private func parseTime(_ time: String) -> DateComponents? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60 else {
            return nil
        }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return components
    }
}
