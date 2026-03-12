import Foundation
import FirebaseFirestore

/// Manages custom reminders (non-medication, non-check-in). Created by member or caregiver.
@MainActor
final class CustomReminderService: ObservableObject {

    // MARK: - State

    @Published var reminders: [CustomReminder] = []

    // MARK: - Dependencies

    private(set) var userId: String
    private(set) var storageService: StorageService?
    private(set) var notificationService: NotificationService?
    private var reminderListener: ListenerRegistration?

    private let collection = "reminders"

    // MARK: - Init

    init(userId: String = "") {
        self.userId = userId
    }

    /// Configure with real dependencies after auth.
    func configure(userId: String, storageService: StorageService, notificationService: NotificationService) {
        self.userId = userId
        self.storageService = storageService
        self.notificationService = notificationService
        startObservingReminders()
    }

    // MARK: - CRUD

    func fetchReminders() async {
        guard let storage = storageService else { return }

        do {
            reminders = try await storage.fetchAll(
                CustomReminder.self,
                from: collection,
                userId: userId,
                limit: 50
            )
        } catch {
            print("[CustomReminderService] Failed to fetch reminders: \(error)")
        }
    }

    private func startObservingReminders() {
        reminderListener?.remove()
        guard let storage = storageService, !userId.isEmpty else { return }

        reminderListener = storage.observe(
            CustomReminder.self,
            in: collection,
            userId: userId
        ) { [weak self] items in
            guard let self else { return }
            self.reminders = items.sorted { lhs, rhs in
                lhs.createdAt < rhs.createdAt
            }
        }
    }

    @discardableResult
    func addReminder(_ reminder: CustomReminder) async -> CustomReminder {
        var saved = reminder

        if let storage = storageService {
            do {
                let docId = try await storage.save(saved, to: collection, userId: userId)
                saved.id = docId
            } catch {
                print("[CustomReminderService] Failed to save reminder: \(error)")
                saved.id = UUID().uuidString
            }
        } else {
            saved.id = UUID().uuidString
        }

        reminders.append(saved)

        if saved.isEnabled {
            await scheduleNotifications(for: saved)
        }

        return saved
    }

    func updateReminder(_ reminder: CustomReminder) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let old = reminders[index]
        reminders[index] = reminder

        if let storage = storageService, let docId = reminder.id {
            do {
                try await storage.save(reminder, to: collection, userId: userId, documentId: docId)
            } catch {
                print("[CustomReminderService] Failed to update reminder: \(error)")
            }
        }

        await cancelNotifications(for: old)
        if reminder.isEnabled {
            await scheduleNotifications(for: reminder)
        }
    }

    func deleteReminder(id: String) async {
        guard let reminder = reminders.first(where: { $0.id == id }) else { return }
        reminders.removeAll { $0.id == id }
        await cancelNotifications(for: reminder)

        if let storage = storageService {
            do {
                try await storage.delete(from: collection, userId: userId, documentId: id)
            } catch {
                print("[CustomReminderService] Failed to delete reminder: \(error)")
            }
        }
    }

    // MARK: - Notifications

    private func scheduleNotifications(for reminder: CustomReminder) async {
        guard let notif = notificationService, let remId = reminder.id else { return }

        for time in reminder.schedule {
            guard let components = parseTime(time) else { continue }

            let mainId = "custom_\(remId)_\(time)"
            let nudgeId = "custom_nudge_\(remId)_\(time)"

            await notif.scheduleNotification(
                id: mainId,
                title: "Reminder",
                body: reminder.title + (reminder.note.map { " — \($0)" } ?? ""),
                at: components,
                category: nil,
                userInfo: [
                    "type": "custom_reminder",
                    "reminderId": remId
                ]
            )

            // Nudge 10 minutes later
            var nudgeComponents = components
            let nudgeMinute = (components.minute ?? 0) + 10
            nudgeComponents.minute = nudgeMinute % 60
            if nudgeMinute >= 60 {
                nudgeComponents.hour = ((components.hour ?? 0) + 1) % 24
            }

            await notif.scheduleNotification(
                id: nudgeId,
                title: "Reminder",
                body: "Don't forget: \(reminder.title)",
                at: nudgeComponents,
                repeats: false,
                userInfo: [
                    "type": "custom_reminder_nudge",
                    "reminderId": remId
                ]
            )
        }
    }

    private func cancelNotifications(for reminder: CustomReminder) async {
        guard let notif = notificationService, let remId = reminder.id else { return }

        var ids: [String] = []
        for time in reminder.schedule {
            ids.append("custom_\(remId)_\(time)")
            ids.append("custom_nudge_\(remId)_\(time)")
        }
        notif.cancelNotifications(ids: ids)
    }

    func rescheduleAllNotifications() async {
        for reminder in reminders where reminder.isEnabled {
            await scheduleNotifications(for: reminder)
        }
    }

    deinit {
        reminderListener?.remove()
    }

    // MARK: - Helpers

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
