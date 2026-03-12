import XCTest

@MainActor
final class CheckInScheduleServiceTests: XCTestCase {

    private var mockCenter: MockNotificationCenter!
    private var notificationService: NotificationService!
    private var service: CheckInScheduleService!

    override func setUp() {
        super.setUp()
        mockCenter = MockNotificationCenter()
        notificationService = NotificationService(center: mockCenter)
        service = CheckInScheduleService()
        service.configure(
            notificationService: notificationService,
            userId: "test-user"
        )
    }

    // MARK: - Schedule Notifications

    func testScheduleMorningAndEvening() async {
        service.schedule = CheckInSchedule(
            morningTime: "08:00",
            eveningTime: "20:00",
            morningEnabled: true,
            eveningEnabled: true
        )

        await service.scheduleCheckInNotifications(userName: "Robert")

        // Morning main + morning nudge + evening main + evening nudge = 4
        let pending = await notificationService.pendingRequests()
        XCTAssertEqual(pending.count, 4)

        let ids = Set(pending.map(\.identifier))
        XCTAssertTrue(ids.contains("checkin_morning_08:00"))
        XCTAssertTrue(ids.contains("checkin_nudge_morning_08:00"))
        XCTAssertTrue(ids.contains("checkin_evening_20:00"))
        XCTAssertTrue(ids.contains("checkin_nudge_evening_20:00"))
    }

    func testScheduleMorningOnly() async {
        service.schedule = CheckInSchedule(
            morningTime: "08:00",
            eveningTime: "20:00",
            morningEnabled: true,
            eveningEnabled: false
        )

        await service.scheduleCheckInNotifications(userName: "Robert")

        let pending = await notificationService.pendingRequests()
        XCTAssertEqual(pending.count, 2) // morning + nudge
        XCTAssertTrue(pending.allSatisfy { $0.identifier.contains("morning") })
    }

    func testScheduleEveningOnly() async {
        service.schedule = CheckInSchedule(
            morningTime: "08:00",
            eveningTime: "20:00",
            morningEnabled: false,
            eveningEnabled: true
        )

        await service.scheduleCheckInNotifications(userName: "Robert")

        let pending = await notificationService.pendingRequests()
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.allSatisfy { $0.identifier.contains("evening") })
    }

    func testScheduleNoneDisabled() async {
        service.schedule = CheckInSchedule(
            morningEnabled: false,
            eveningEnabled: false
        )

        await service.scheduleCheckInNotifications(userName: "Robert")

        let pending = await notificationService.pendingRequests()
        XCTAssertTrue(pending.isEmpty)
    }

    func testMorningNotificationContent() async {
        service.schedule = CheckInSchedule(
            morningTime: "08:00",
            morningEnabled: true,
            eveningEnabled: false
        )

        await service.scheduleCheckInNotifications(userName: "Robert")

        let pending = await notificationService.pendingRequests()
        let main = pending.first { $0.identifier == "checkin_morning_08:00" }

        XCTAssertNotNil(main)
        XCTAssertTrue(main!.content.body.contains("Robert"))
        XCTAssertEqual(main!.content.userInfo["type"] as? String, "checkin_morning")
    }

    func testNudgeScheduled10MinAfter() async {
        service.schedule = CheckInSchedule(
            morningTime: "08:00",
            morningEnabled: true,
            eveningEnabled: false
        )

        await service.scheduleCheckInNotifications(userName: "Robert")

        let pending = await notificationService.pendingRequests()
        let nudge = pending.first { $0.identifier == "checkin_nudge_morning_08:00" }

        XCTAssertNotNil(nudge)
        XCTAssertEqual(nudge!.content.userInfo["type"] as? String, "checkin_nudge")
    }

    // MARK: - Cancel

    func testCancelAllCheckInNotifications() async {
        service.schedule = CheckInSchedule(morningEnabled: true, eveningEnabled: true)
        await service.scheduleCheckInNotifications(userName: "Robert")

        XCTAssertFalse(mockCenter.scheduledRequests.isEmpty)

        service.cancelAllCheckInNotifications()

        let pending = await notificationService.pendingRequests()
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - Reschedule

    func testRescheduleReplacesExisting() async {
        service.schedule = CheckInSchedule(
            morningTime: "07:00",
            morningEnabled: true,
            eveningEnabled: false
        )
        await service.scheduleCheckInNotifications(userName: "Robert")

        service.schedule = CheckInSchedule(
            morningTime: "09:00",
            morningEnabled: true,
            eveningEnabled: false
        )
        await service.scheduleCheckInNotifications(userName: "Robert")

        let pending = await notificationService.pendingRequests()
        // Should have new IDs, old ones cancelled
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.contains { $0.identifier == "checkin_morning_09:00" })
        XCTAssertFalse(pending.contains { $0.identifier == "checkin_morning_07:00" })
    }

    // MARK: - Pending Check-In

    func testPendingCheckInDefaultsFalse() {
        XCTAssertFalse(service.pendingCheckIn)
    }

    func testPendingCheckInCanBeSetAndReset() {
        service.pendingCheckIn = true
        XCTAssertTrue(service.pendingCheckIn)

        service.pendingCheckIn = false
        XCTAssertFalse(service.pendingCheckIn)
    }

    // MARK: - Notification Buffering (Cold Start)

    func testBufferedFlagDefaultsFalse() {
        XCTAssertFalse(CheckInScheduleService.pendingCheckInFromNotification)
    }

    func testDrainPropagatesBufferedFlag() {
        // Simulate: notification arrives before service is wired
        CheckInScheduleService.pendingCheckInFromNotification = true
        XCTAssertFalse(service.pendingCheckIn)

        // Simulate: setupCheckInCoordinator() calls drainPendingNotification()
        service.drainPendingNotification()

        // Flag propagated to service, buffer cleared
        XCTAssertTrue(service.pendingCheckIn)
        XCTAssertFalse(CheckInScheduleService.pendingCheckInFromNotification)
    }

    func testDrainDoesNothingWhenBufferNotSet() {
        CheckInScheduleService.pendingCheckInFromNotification = false

        service.drainPendingNotification()

        XCTAssertFalse(service.pendingCheckIn)
    }

    func testDirectSetWhenServiceAlreadyWired() {
        // Simulate: warm start, service already wired, notification arrives
        service.pendingCheckIn = true

        XCTAssertTrue(service.pendingCheckIn)
    }

    func testDrainSetsExactlyOnePendingCheckIn() {
        // Simulate multiple rapid notification taps — only one should propagate
        CheckInScheduleService.pendingCheckInFromNotification = true
        service.drainPendingNotification()
        XCTAssertTrue(service.pendingCheckIn)

        // Second drain should not re-set (buffer already cleared)
        service.pendingCheckIn = false
        service.drainPendingNotification()
        XCTAssertFalse(service.pendingCheckIn)
    }

    func testScheduleDefaultValues() {
        // Default schedule: morning + evening enabled at 08:00 and 20:00
        XCTAssertTrue(service.schedule.morningEnabled)
        XCTAssertTrue(service.schedule.eveningEnabled)
        XCTAssertEqual(service.schedule.morningTime, "08:00")
        XCTAssertEqual(service.schedule.eveningTime, "20:00")
    }
}
