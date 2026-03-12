import XCTest
import UserNotifications

@MainActor
final class NotificationServiceTests: XCTestCase {

    private var mockCenter: MockNotificationCenter!
    private var service: NotificationService!

    override func setUp() {
        super.setUp()
        mockCenter = MockNotificationCenter()
        service = NotificationService(center: mockCenter)
    }

    // MARK: - Permission

    func testRequestPermissionGranted() async {
        mockCenter.authorizationGranted = true
        let granted = await service.requestPermission()
        XCTAssertTrue(granted)
        XCTAssertTrue(service.isAuthorized)
    }

    func testRequestPermissionDenied() async {
        mockCenter.authorizationGranted = false
        let granted = await service.requestPermission()
        XCTAssertFalse(granted)
        XCTAssertFalse(service.isAuthorized)
    }

    func testRequestPermissionError() async {
        mockCenter.authorizationError = NSError(domain: "test", code: -1)
        let granted = await service.requestPermission()
        XCTAssertFalse(granted)
        XCTAssertFalse(service.isAuthorized)
    }

    // MARK: - Categories

    func testRegisterCategoriesAddsMedicationCategory() {
        service.registerCategories()
        XCTAssertEqual(mockCenter.registeredCategories.count, 1)

        let category = mockCenter.registeredCategories.first
        XCTAssertEqual(category?.identifier, NotificationService.medicationCategoryId)
        XCTAssertEqual(category?.actions.count, 3)
        XCTAssertEqual(category?.actions[0].identifier, NotificationService.takenActionId)
        XCTAssertEqual(category?.actions[1].identifier, NotificationService.notYetActionId)
        XCTAssertEqual(category?.actions[2].identifier, NotificationService.snoozeActionId)
    }

    // MARK: - Schedule

    func testScheduleAddsRequest() async {
        var components = DateComponents()
        components.hour = 8
        components.minute = 0

        await service.scheduleNotification(
            id: "test_1",
            title: "Test",
            body: "Test body",
            at: components,
            category: "test_category",
            userInfo: ["key": "value"]
        )

        let pending = await service.pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].identifier, "test_1")
        XCTAssertEqual(pending[0].content.title, "Test")
        XCTAssertEqual(pending[0].content.body, "Test body")
        XCTAssertEqual(pending[0].content.categoryIdentifier, "test_category")
        XCTAssertEqual(pending[0].content.userInfo["key"] as? String, "value")
    }

    func testScheduleReplacesExistingWithSameId() async {
        var components = DateComponents()
        components.hour = 8

        await service.scheduleNotification(id: "test_1", title: "First", body: "1", at: components)
        await service.scheduleNotification(id: "test_1", title: "Second", body: "2", at: components)

        let pending = await service.pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].content.title, "Second")
    }

    func testScheduleAfterDelay() async {
        await service.scheduleNotificationAfter(
            id: "delayed_1",
            title: "Nudge",
            body: "Don't forget!",
            delay: 900,
            category: "medication_reminder"
        )

        let pending = await service.pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].identifier, "delayed_1")
    }

    // MARK: - Cancel

    func testCancelRemovesById() async {
        var components = DateComponents()
        components.hour = 8

        await service.scheduleNotification(id: "keep", title: "Keep", body: "", at: components)
        await service.scheduleNotification(id: "remove", title: "Remove", body: "", at: components)

        service.cancelNotification(id: "remove")

        let pending = await service.pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].identifier, "keep")
    }

    func testCancelMultipleByIds() async {
        var components = DateComponents()
        components.hour = 8

        await service.scheduleNotification(id: "a", title: "A", body: "", at: components)
        await service.scheduleNotification(id: "b", title: "B", body: "", at: components)
        await service.scheduleNotification(id: "c", title: "C", body: "", at: components)

        service.cancelNotifications(ids: ["a", "c"])

        let pending = await service.pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].identifier, "b")
    }

    func testCancelAllRemovesEverything() async {
        var components = DateComponents()
        components.hour = 8

        await service.scheduleNotification(id: "a", title: "A", body: "", at: components)
        await service.scheduleNotification(id: "b", title: "B", body: "", at: components)

        service.cancelAllNotifications()

        let pending = await service.pendingRequests()
        XCTAssertTrue(pending.isEmpty)
    }
}
