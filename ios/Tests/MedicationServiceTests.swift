import XCTest

@MainActor
final class MedicationServiceTests: XCTestCase {

    private var mockCenter: MockNotificationCenter!
    private var notificationService: NotificationService!
    private var service: MedicationService!

    override func setUp() {
        super.setUp()
        mockCenter = MockNotificationCenter()
        notificationService = NotificationService(center: mockCenter)
        service = MedicationService(
            userId: "test-user",
            storageService: nil,
            notificationService: notificationService
        )
    }

    // MARK: - Add / Fetch

    func testFetchReturnsEmpty() async {
        let meds = await service.fetchMedications()
        XCTAssertTrue(meds.isEmpty)
    }

    func testAddMedicationStoresInCache() async {
        let med = await service.addMedication(
            name: "Levodopa",
            dosage: "100mg",
            form: "pill",
            schedule: ["08:00", "20:00"]
        )

        XCTAssertEqual(med.name, "Levodopa")
        XCTAssertEqual(med.dosage, "100mg")
        XCTAssertEqual(med.schedule, ["08:00", "20:00"])
        XCTAssertTrue(med.isActive)
        XCTAssertFalse(med.reminderEnabled)
        XCTAssertNotNil(med.id)
        XCTAssertEqual(service.medications.count, 1)
    }

    func testAddMultipleMedications() async {
        await service.addMedication(name: "Med A")
        await service.addMedication(name: "Med B")
        await service.addMedication(name: "Med C")

        XCTAssertEqual(service.medications.count, 3)
    }

    // MARK: - Update

    func testUpdateChangesFields() async {
        var med = await service.addMedication(name: "Original", dosage: "50mg")

        med.name = "Updated"
        med.dosage = "100mg"
        await service.updateMedication(med)

        XCTAssertEqual(service.medications.count, 1)
        XCTAssertEqual(service.medications[0].name, "Updated")
        XCTAssertEqual(service.medications[0].dosage, "100mg")
    }

    func testUpdateNonexistentDoesNothing() async {
        var med = Medication(userId: "test-user", name: "Ghost")
        med.id = "nonexistent"

        await service.updateMedication(med)
        XCTAssertTrue(service.medications.isEmpty)
    }

    // MARK: - Delete

    func testDeleteRemoves() async {
        let med = await service.addMedication(name: "ToDelete")
        XCTAssertEqual(service.medications.count, 1)

        await service.deleteMedication(id: med.id!)
        XCTAssertTrue(service.medications.isEmpty)
    }

    func testDeleteNonexistentDoesNothing() async {
        await service.addMedication(name: "Keep")
        await service.deleteMedication(id: "nonexistent")
        XCTAssertEqual(service.medications.count, 1)
    }

    // MARK: - Deactivate

    func testDeactivateSetsInactive() async {
        let med = await service.addMedication(
            name: "Active",
            schedule: ["09:00"],
            reminderEnabled: true
        )

        await service.deactivateMedication(id: med.id!)

        XCTAssertEqual(service.medications.count, 1)
        XCTAssertFalse(service.medications[0].isActive)
        XCTAssertFalse(service.medications[0].reminderEnabled)
    }

    // MARK: - Reminder Scheduling

    func testAddWithRemindersSchedulesNotifications() async {
        await service.addMedication(
            name: "Levodopa",
            schedule: ["08:00", "20:00"],
            reminderEnabled: true
        )

        // 2 times × 2 notifications (main + nudge) = 4
        XCTAssertEqual(mockCenter.scheduledRequests.count, 4)

        let ids = Set(mockCenter.scheduledRequests.map(\.identifier))
        let medId = service.medications[0].id!
        XCTAssertTrue(ids.contains("med_\(medId)_08:00"))
        XCTAssertTrue(ids.contains("med_nudge_\(medId)_08:00"))
        XCTAssertTrue(ids.contains("med_\(medId)_20:00"))
        XCTAssertTrue(ids.contains("med_nudge_\(medId)_20:00"))
    }

    func testAddWithoutRemindersDoesNotSchedule() async {
        await service.addMedication(
            name: "NoReminder",
            schedule: ["08:00"],
            reminderEnabled: false
        )

        XCTAssertTrue(mockCenter.scheduledRequests.isEmpty)
    }

    func testDeactivateCancelsReminders() async {
        let med = await service.addMedication(
            name: "Active",
            schedule: ["09:00"],
            reminderEnabled: true
        )

        XCTAssertEqual(mockCenter.scheduledRequests.count, 2)

        await service.deactivateMedication(id: med.id!)
        XCTAssertTrue(mockCenter.scheduledRequests.isEmpty)
    }

    func testDeleteCancelsReminders() async {
        let med = await service.addMedication(
            name: "ToDelete",
            schedule: ["10:00"],
            reminderEnabled: true
        )

        XCTAssertEqual(mockCenter.scheduledRequests.count, 2)

        await service.deleteMedication(id: med.id!)
        XCTAssertTrue(mockCenter.scheduledRequests.isEmpty)
    }

    func testRescheduleAllOnLaunch() async {
        await service.addMedication(name: "A", schedule: ["08:00"], reminderEnabled: true)
        await service.addMedication(name: "B", schedule: ["09:00"], reminderEnabled: true)
        await service.addMedication(name: "C", schedule: ["10:00"], reminderEnabled: false)

        // A: 2 notifications, B: 2 notifications = 4
        XCTAssertEqual(mockCenter.scheduledRequests.count, 4)

        // Simulate app restart — cancelAll + reschedule
        await service.rescheduleAllReminders()

        // Should still be 4 (only A and B have reminders)
        XCTAssertEqual(mockCenter.scheduledRequests.count, 4)
    }

    func testNotificationContent() async {
        await service.addMedication(
            name: "Aspirin",
            dosage: "81mg",
            schedule: ["07:30"],
            reminderEnabled: true
        )

        let mainRequest = mockCenter.scheduledRequests.first { $0.identifier.hasPrefix("med_") && !$0.identifier.contains("nudge") }
        XCTAssertNotNil(mainRequest)
        XCTAssertEqual(mainRequest?.content.title, "Medication Reminder")
        XCTAssertEqual(mainRequest?.content.body, "Time to take Aspirin (81mg)")
        XCTAssertEqual(mainRequest?.content.categoryIdentifier, NotificationService.medicationCategoryId)
        XCTAssertEqual(mainRequest?.content.userInfo["medicationName"] as? String, "Aspirin")
        XCTAssertEqual(mainRequest?.content.userInfo["type"] as? String, "medication_reminder")
    }

    func testNudgeContent() async {
        await service.addMedication(
            name: "Aspirin",
            schedule: ["07:30"],
            reminderEnabled: true
        )

        let nudge = mockCenter.scheduledRequests.first { $0.identifier.contains("nudge") }
        XCTAssertNotNil(nudge)
        XCTAssertEqual(nudge?.content.title, "Reminder")
        XCTAssertEqual(nudge?.content.body, "Have you taken Aspirin?")
        XCTAssertEqual(nudge?.content.userInfo["type"] as? String, "medication_nudge")
    }

    func testUpdateReschedulesReminders() async {
        var med = await service.addMedication(
            name: "Med",
            schedule: ["08:00"],
            reminderEnabled: true
        )
        XCTAssertEqual(mockCenter.scheduledRequests.count, 2)

        med.schedule = ["08:00", "14:00"]
        await service.updateMedication(med)

        // Old cancelled, new scheduled: 2 times × 2 = 4
        XCTAssertEqual(mockCenter.scheduledRequests.count, 4)
    }

    // MARK: - Adherence Logging

    func testLogAdherenceTaken() async {
        // Just verify it doesn't crash without StorageService
        await service.logAdherence(
            medicationId: "med-1",
            medicationName: "Levodopa",
            status: .taken,
            scheduledTime: "08:00",
            reportedVia: "notification"
        )
        // No assertion needed — verifying no crash. Real test needs StorageService mock.
    }

    func testLogAdherenceSkipped() async {
        await service.logAdherence(
            medicationId: "med-1",
            medicationName: "Levodopa",
            status: .skipped,
            scheduledTime: "08:00",
            reportedVia: "notification"
        )
    }
}
