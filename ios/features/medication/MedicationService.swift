import Foundation

/// Manages medication CRUD, reminder scheduling, and adherence logging.
@MainActor
final class MedicationService: ObservableObject {

    // MARK: - State

    @Published var medications: [Medication] = []

    /// Set when user taps a medication notification. CompanionHomeView reads this to have Mira speak.
    @Published var pendingMedicationMessage: String?

    // MARK: - Dependencies

    private(set) var userId: String
    private(set) var storageService: StorageService?
    private(set) var notificationService: NotificationService?

    private let medicationCollection = "medications"
    private let adherenceCollection = "medication_adherence"

    // MARK: - Init

    init(
        userId: String,
        storageService: StorageService? = nil,
        notificationService: NotificationService? = nil
    ) {
        self.userId = userId
        self.storageService = storageService
        self.notificationService = notificationService
    }

    /// Reconfigure with real dependencies after auth.
    func configure(userId: String, storageService: StorageService, notificationService: NotificationService) {
        self.userId = userId
        self.storageService = storageService
        self.notificationService = notificationService
    }

    // MARK: - CRUD

    /// Adds a new medication. Schedules reminders if enabled.
    @discardableResult
    func addMedication(
        name: String,
        dosage: String? = nil,
        form: String? = nil,
        schedule: [String] = [],
        reminderEnabled: Bool = false
    ) async -> Medication {
        var med = Medication(
            userId: userId,
            name: name,
            dosage: dosage,
            form: form,
            schedule: schedule,
            reminderEnabled: reminderEnabled
        )

        if let storage = storageService {
            do {
                var toSave = med
                let enc = storage.encryptionService
                let key = try enc.getOrCreateKey(for: userId)
                try toSave.encryptFields(using: enc, key: key)
                let docId = try await storage.save(toSave, to: medicationCollection, userId: userId)
                med.id = docId
            } catch {
                print("[MedicationService] Failed to save medication: \(error)")
            }
        } else {
            med.id = UUID().uuidString
        }

        medications.append(med)

        if reminderEnabled {
            await scheduleReminders(for: med)
        }

        return med
    }

    /// Fetches all medications from Firestore (or returns local cache).
    func fetchMedications() async -> [Medication] {
        guard let storage = storageService else { return medications }

        do {
            var fetched = try await storage.fetchAll(
                Medication.self,
                from: medicationCollection,
                userId: userId
            )
            // Decrypt sensitive fields after loading from Firestore
            let enc = storage.encryptionService
            let key = try enc.getOrCreateKey(for: userId)
            for i in fetched.indices {
                try fetched[i].decryptFields(using: enc, key: key)
            }
            medications = fetched
        } catch {
            print("[MedicationService] Failed to fetch medications: \(error)")
        }
        return medications
    }

    /// Updates a medication in-place. Reschedules reminders if needed.
    func updateMedication(_ medication: Medication) async {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        let old = medications[index]
        medications[index] = medication

        if let storage = storageService, let docId = medication.id {
            do {
                var toSave = medication
                let enc = storage.encryptionService
                let key = try enc.getOrCreateKey(for: userId)
                try toSave.encryptFields(using: enc, key: key)
                try await storage.save(toSave, to: medicationCollection, userId: userId, documentId: docId)
            } catch {
                print("[MedicationService] Failed to update medication: \(error)")
            }
        }

        // Cancel old reminders and reschedule if still enabled
        await cancelReminders(for: old)
        if medication.reminderEnabled && medication.isActive {
            await scheduleReminders(for: medication)
        }
    }

    /// Deletes a medication permanently.
    func deleteMedication(id: String) async {
        guard let med = medications.first(where: { $0.id == id }) else { return }
        medications.removeAll { $0.id == id }
        await cancelReminders(for: med)

        if let storage = storageService {
            do {
                try await storage.delete(from: medicationCollection, userId: userId, documentId: id)
            } catch {
                print("[MedicationService] Failed to delete medication: \(error)")
            }
        }
    }

    /// Deactivates a medication (keeps history, stops reminders).
    func deactivateMedication(id: String) async {
        guard let index = medications.firstIndex(where: { $0.id == id }) else { return }
        medications[index].isActive = false
        medications[index].reminderEnabled = false

        let med = medications[index]
        await cancelReminders(for: med)

        if let storage = storageService, let docId = med.id {
            do {
                var toSave = med
                let enc = storage.encryptionService
                let key = try enc.getOrCreateKey(for: userId)
                try toSave.encryptFields(using: enc, key: key)
                try await storage.save(toSave, to: medicationCollection, userId: userId, documentId: docId)
            } catch {
                print("[MedicationService] Failed to deactivate medication: \(error)")
            }
        }
    }

    // MARK: - Adherence

    /// Logs a medication adherence event.
    func logAdherence(
        medicationId: String?,
        medicationName: String,
        status: MedicationStatus,
        scheduledTime: String? = nil,
        reportedVia: String = "manual"
    ) async {
        let entry = MedicationAdherenceEntry(
            medicationId: medicationId,
            medicationName: medicationName,
            status: status,
            scheduledTime: scheduledTime,
            takenAt: status == .taken ? Date() : nil,
            reportedVia: reportedVia
        )

        if let storage = storageService {
            do {
                var toSave = entry
                let enc = storage.encryptionService
                let key = try enc.getOrCreateKey(for: userId)
                try toSave.encryptFields(using: enc, key: key)
                try await storage.save(toSave, to: adherenceCollection, userId: userId)
            } catch {
                print("[MedicationService] Failed to log adherence: \(error)")
            }
        }

        print("[MedicationService] Logged \(status.rawValue) for \(medicationName)")
    }

    // MARK: - Reminder Scheduling

    /// Schedules notifications for all time slots of a medication.
    private func scheduleReminders(for medication: Medication) async {
        guard let notif = notificationService, let medId = medication.id else { return }

        for time in medication.schedule {
            guard let components = parseTime(time) else { continue }

            let mainId = "med_\(medId)_\(time)"
            let nudgeId = "med_nudge_\(medId)_\(time)"

            // Main reminder
            await notif.scheduleNotification(
                id: mainId,
                title: "Medication Reminder",
                body: "Time to take \(medication.name)" + (medication.dosage.map { " (\($0))" } ?? ""),
                at: components,
                category: NotificationService.medicationCategoryId,
                userInfo: [
                    "medicationId": medId,
                    "medicationName": medication.name,
                    "scheduledTime": time,
                    "type": "medication_reminder"
                ]
            )

            // Nudge 15 minutes later
            var nudgeComponents = components
            let nudgeMinute = (components.minute ?? 0) + 15
            nudgeComponents.minute = nudgeMinute % 60
            if nudgeMinute >= 60 {
                nudgeComponents.hour = ((components.hour ?? 0) + 1) % 24
            }

            await notif.scheduleNotification(
                id: nudgeId,
                title: "Reminder",
                body: "Have you taken \(medication.name)?",
                at: nudgeComponents,
                repeats: false,
                category: NotificationService.medicationCategoryId,
                userInfo: [
                    "medicationId": medId,
                    "medicationName": medication.name,
                    "scheduledTime": time,
                    "type": "medication_nudge"
                ]
            )
        }
    }

    /// Cancels all notifications for a medication.
    private func cancelReminders(for medication: Medication) async {
        guard let notif = notificationService, let medId = medication.id else { return }

        var ids: [String] = []
        for time in medication.schedule {
            ids.append("med_\(medId)_\(time)")
            ids.append("med_nudge_\(medId)_\(time)")
        }
        notif.cancelNotifications(ids: ids)
    }

    /// Reschedules all active reminders. Call on app launch.
    func rescheduleAllReminders() async {
        notificationService?.cancelAllNotifications()

        for med in medications where med.reminderEnabled && med.isActive {
            await scheduleReminders(for: med)
        }
        print("[MedicationService] Rescheduled reminders for \(medications.filter { $0.reminderEnabled && $0.isActive }.count) medications")
    }

    // MARK: - Helpers

    /// Parses "HH:mm" into DateComponents with hour and minute.
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
