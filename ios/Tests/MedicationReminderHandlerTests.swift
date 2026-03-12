import XCTest

@MainActor
final class MedicationReminderHandlerTests: XCTestCase {

    private var mockCenter: MockNotificationCenter!
    private var notificationService: NotificationService!
    private var medicationService: MedicationService!
    private var defaults: UserDefaults!
    private var handler: MedicationReminderHandler!

    private let testUserInfo: [AnyHashable: Any] = [
        "medicationId": "med-123",
        "medicationName": "Levodopa",
        "scheduledTime": "08:00",
        "type": "medication_reminder"
    ]

    override func setUp() {
        super.setUp()
        mockCenter = MockNotificationCenter()
        notificationService = NotificationService(center: mockCenter)
        medicationService = MedicationService(
            userId: "test-user",
            storageService: nil,
            notificationService: notificationService
        )
        defaults = UserDefaults(suiteName: "MedicationReminderHandlerTests")!
        defaults.removePersistentDomain(forName: "MedicationReminderHandlerTests")

        handler = MedicationReminderHandler(
            medicationService: medicationService,
            notificationService: notificationService,
            defaults: defaults
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "MedicationReminderHandlerTests")
        super.tearDown()
    }

    // MARK: - Taken Action

    func testHandleTakenCancelsNudge() async {
        // Pre-schedule a nudge notification
        await notificationService.scheduleNotificationAfter(
            id: "med_nudge_med-123_08:00",
            title: "Nudge",
            body: "Take it",
            delay: 900
        )
        XCTAssertEqual(mockCenter.scheduledRequests.count, 1)

        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.takenActionId,
            userInfo: testUserInfo
        )

        // Nudge should be cancelled
        XCTAssertTrue(mockCenter.scheduledRequests.isEmpty)
    }

    func testHandleTakenResetsSnoozeCount() async {
        let snoozeKey = "med_snooze_med-123_08:00"
        defaults.set(2, forKey: snoozeKey)

        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.takenActionId,
            userInfo: testUserInfo
        )

        XCTAssertEqual(defaults.integer(forKey: snoozeKey), 0)
    }

    // MARK: - Snooze Action

    func testSnoozeReschedulesFor30Min() async {
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )

        // Should have scheduled a snooze notification
        XCTAssertEqual(mockCenter.scheduledRequests.count, 1)
        let request = mockCenter.scheduledRequests[0]
        XCTAssertTrue(request.identifier.contains("med_snooze_med-123_08:00"))
        XCTAssertEqual(request.content.categoryIdentifier, NotificationService.medicationCategoryId)
    }

    func testSnoozeCountIncrements() async {
        let snoozeKey = "med_snooze_med-123_08:00"
        XCTAssertEqual(defaults.integer(forKey: snoozeKey), 0)

        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )
        XCTAssertEqual(defaults.integer(forKey: snoozeKey), 1)

        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )
        XCTAssertEqual(defaults.integer(forKey: snoozeKey), 2)
    }

    func testMaxSnoozesMarksSkipped() async {
        let snoozeKey = "med_snooze_med-123_08:00"
        defaults.set(3, forKey: snoozeKey) // Already at max

        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )

        // No new notification scheduled
        XCTAssertTrue(mockCenter.scheduledRequests.isEmpty)

        // Snooze count reset after marking skipped
        XCTAssertEqual(defaults.integer(forKey: snoozeKey), 0)
    }

    func testSnoozeThreeTimesThenMaxed() async {
        // Snooze 1
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )
        XCTAssertEqual(mockCenter.scheduledRequests.count, 1)

        // Snooze 2
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )
        XCTAssertEqual(mockCenter.scheduledRequests.count, 2)

        // Snooze 3
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )
        XCTAssertEqual(mockCenter.scheduledRequests.count, 3)

        // Snooze 4 — should be max, no new notification
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.snoozeActionId,
            userInfo: testUserInfo
        )
        // Still 3 from before — no new one added
        XCTAssertEqual(mockCenter.scheduledRequests.count, 3)
    }

    // MARK: - Not Yet Action

    func testNotYetCancelsNudge() async {
        // Pre-schedule a nudge
        await notificationService.scheduleNotificationAfter(
            id: "med_nudge_med-123_08:00",
            title: "Nudge",
            body: "Take it",
            delay: 900
        )
        XCTAssertEqual(mockCenter.scheduledRequests.count, 1)

        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.notYetActionId,
            userInfo: testUserInfo
        )

        // Nudge cancelled, but 1-hour re-remind scheduled
        XCTAssertEqual(mockCenter.scheduledRequests.count, 1)
        XCTAssertTrue(mockCenter.scheduledRequests[0].identifier.contains("med_notyet_med-123_08:00"))
    }

    func testNotYetSchedules1HourReRemind() async {
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.notYetActionId,
            userInfo: testUserInfo
        )

        XCTAssertEqual(mockCenter.scheduledRequests.count, 1)
        let request = mockCenter.scheduledRequests[0]
        XCTAssertEqual(request.identifier, "med_notyet_med-123_08:00")
        XCTAssertEqual(request.content.categoryIdentifier, NotificationService.medicationCategoryId)
        XCTAssertEqual(request.content.userInfo["type"] as? String, "medication_notyet")
    }

    // MARK: - Default Tap

    func testDefaultTapSetsPendingMedicationId() async {
        XCTAssertNil(handler.pendingMedicationId)

        await handler.handleNotificationResponse(
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
            userInfo: testUserInfo
        )

        XCTAssertEqual(handler.pendingMedicationId, "med-123")
    }

    // MARK: - Missing userInfo

    func testMissingUserInfoDoesNotCrash() async {
        await handler.handleNotificationResponse(
            actionIdentifier: NotificationService.takenActionId,
            userInfo: [:]
        )
        // No crash, no side effects
        XCTAssertTrue(mockCenter.scheduledRequests.isEmpty)
    }
}
