import Foundation

/// Processes notification responses for medication reminders (Taken, Snooze, default tap).
@MainActor
final class MedicationReminderHandler: ObservableObject {

    // MARK: - Constants

    static let maxSnoozeCount = 3
    static let snoozeDelaySeconds: TimeInterval = 30 * 60 // 30 minutes
    static let notYetDelaySeconds: TimeInterval = 60 * 60 // 1 hour

    // MARK: - State

    /// Set when user taps the notification body (not an action button). UI reads this to show context.
    @Published var pendingMedicationId: String?

    // MARK: - Dependencies

    private let medicationService: MedicationService
    private let notificationService: NotificationService
    private let defaults: UserDefaults

    // MARK: - Init

    init(
        medicationService: MedicationService,
        notificationService: NotificationService,
        defaults: UserDefaults = .standard
    ) {
        self.medicationService = medicationService
        self.notificationService = notificationService
        self.defaults = defaults
    }

    // MARK: - Handle Notification Response

    /// Called by the notification delegate when user interacts with a medication notification.
    func handleNotificationResponse(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async {
        guard let medicationId = userInfo["medicationId"] as? String,
              let medicationName = userInfo["medicationName"] as? String,
              let scheduledTime = userInfo["scheduledTime"] as? String else {
            print("[MedicationReminderHandler] Missing userInfo fields")
            return
        }

        switch actionIdentifier {
        case NotificationService.takenActionId:
            await handleTaken(medicationId: medicationId, medicationName: medicationName, scheduledTime: scheduledTime)

        case NotificationService.notYetActionId:
            await handleNotYet(medicationId: medicationId, medicationName: medicationName, scheduledTime: scheduledTime)

        case NotificationService.snoozeActionId:
            await handleSnooze(medicationId: medicationId, medicationName: medicationName, scheduledTime: scheduledTime)

        default:
            // Default tap — open the app and have Mira speak the reminder
            handleDefaultTap(medicationId: medicationId, medicationName: medicationName, scheduledTime: scheduledTime)
        }
    }

    // MARK: - Taken

    private func handleTaken(medicationId: String, medicationName: String, scheduledTime: String) async {
        // Log adherence
        await medicationService.logAdherence(
            medicationId: medicationId,
            medicationName: medicationName,
            status: .taken,
            scheduledTime: scheduledTime,
            reportedVia: "notification"
        )

        // Cancel the nudge notification
        let nudgeId = "med_nudge_\(medicationId)_\(scheduledTime)"
        notificationService.cancelNotification(id: nudgeId)

        // Reset snooze count
        let snoozeKey = snoozeCountKey(medicationId: medicationId, time: scheduledTime)
        defaults.removeObject(forKey: snoozeKey)

        // Haptic + audio feedback
        HapticService.medicationTaken()
        AudioCueService.playMedicationTaken()

        print("[MedicationReminderHandler] Taken: \(medicationName) at \(scheduledTime)")
    }

    // MARK: - Not Yet (1 hour re-remind)

    private func handleNotYet(medicationId: String, medicationName: String, scheduledTime: String) async {
        // Log as delayed
        await medicationService.logAdherence(
            medicationId: medicationId,
            medicationName: medicationName,
            status: .delayed,
            scheduledTime: scheduledTime,
            reportedVia: "notification"
        )

        // Cancel the nudge since user acknowledged
        let nudgeId = "med_nudge_\(medicationId)_\(scheduledTime)"
        notificationService.cancelNotification(id: nudgeId)

        // Schedule re-remind in 1 hour
        let notYetId = "med_notyet_\(medicationId)_\(scheduledTime)"
        await notificationService.scheduleNotificationAfter(
            id: notYetId,
            title: "Medication Reminder",
            body: "Checking back — did you take \(medicationName)?",
            delay: Self.notYetDelaySeconds,
            category: NotificationService.medicationCategoryId,
            userInfo: [
                "medicationId": medicationId,
                "medicationName": medicationName,
                "scheduledTime": scheduledTime,
                "type": "medication_notyet"
            ]
        )

        print("[MedicationReminderHandler] Not yet: \(medicationName), re-remind in 1 hour")
    }

    // MARK: - Snooze

    private func handleSnooze(medicationId: String, medicationName: String, scheduledTime: String) async {
        let snoozeKey = snoozeCountKey(medicationId: medicationId, time: scheduledTime)
        let currentCount = defaults.integer(forKey: snoozeKey)

        if currentCount >= Self.maxSnoozeCount {
            // Max snoozes reached — mark as skipped
            await medicationService.logAdherence(
                medicationId: medicationId,
                medicationName: medicationName,
                status: .skipped,
                scheduledTime: scheduledTime,
                reportedVia: "notification"
            )
            defaults.removeObject(forKey: snoozeKey)
            print("[MedicationReminderHandler] Max snoozes reached for \(medicationName), marked skipped")
            return
        }

        // Increment snooze count
        defaults.set(currentCount + 1, forKey: snoozeKey)

        // Schedule a new notification in 30 minutes
        let snoozeId = "med_snooze_\(medicationId)_\(scheduledTime)_\(currentCount + 1)"
        await notificationService.scheduleNotificationAfter(
            id: snoozeId,
            title: "Medication Reminder",
            body: "Snoozed: Time to take \(medicationName)",
            delay: Self.snoozeDelaySeconds,
            category: NotificationService.medicationCategoryId,
            userInfo: [
                "medicationId": medicationId,
                "medicationName": medicationName,
                "scheduledTime": scheduledTime,
                "type": "medication_snooze"
            ]
        )

        print("[MedicationReminderHandler] Snoozed \(medicationName) (\(currentCount + 1)/\(Self.maxSnoozeCount))")
    }

    // MARK: - Default Tap

    private func handleDefaultTap(medicationId: String, medicationName: String, scheduledTime: String) {
        pendingMedicationId = medicationId

        // Build a spoken message with name + dosage
        let med = medicationService.medications.first { $0.id == medicationId }
        let dosageInfo = med?.dosage.map { ", \($0)" } ?? ""
        let message = "Hi! It's time to take your \(medicationName)\(dosageInfo). Have you taken it yet?"
        medicationService.pendingMedicationMessage = message

        print("[MedicationReminderHandler] Default tap: \(medicationId) — queued voice reminder")
    }

    // MARK: - Helpers

    private func snoozeCountKey(medicationId: String, time: String) -> String {
        "med_snooze_\(medicationId)_\(time)"
    }
}
