import Foundation
import UserNotifications

// MARK: - NotificationCenter Protocol

/// Abstracts UNUserNotificationCenter so NotificationService can be tested with a mock.
protocol NotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

/// Real implementation wrapping UNUserNotificationCenter.
final class SystemNotificationCenter: NotificationCenterProtocol {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
}

/// In-memory mock for unit tests.
final class MockNotificationCenter: NotificationCenterProtocol {
    var authorizationGranted = true
    var authorizationError: Error?
    private(set) var scheduledRequests: [UNNotificationRequest] = []
    private(set) var registeredCategories: Set<UNNotificationCategory> = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        if let error = authorizationError { throw error }
        return authorizationGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        // Replace existing request with same ID (idempotent)
        scheduledRequests.removeAll { $0.identifier == request.identifier }
        scheduledRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        let idSet = Set(identifiers)
        scheduledRequests.removeAll { idSet.contains($0.identifier) }
    }

    func removeAllPendingNotificationRequests() {
        scheduledRequests.removeAll()
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        scheduledRequests
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategories = categories
    }
}

// MARK: - NotificationService

/// Reusable notification scheduling service. Wraps UNUserNotificationCenter with testable protocol.
@MainActor
final class NotificationService: ObservableObject {

    // MARK: - Constants

    static let medicationCategoryId = "medication_reminder"
    static let takenActionId = "TAKEN_ACTION"
    static let snoozeActionId = "SNOOZE_ACTION"
    static let notYetActionId = "NOT_YET_ACTION"

    // MARK: - State

    @Published var isAuthorized: Bool = false

    // MARK: - Dependencies

    let center: NotificationCenterProtocol

    // MARK: - Init

    init(center: NotificationCenterProtocol = SystemNotificationCenter()) {
        self.center = center
    }

    // MARK: - Permission

    /// Requests notification permission. Returns true if granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            print("[NotificationService] Permission request failed: \(error)")
            isAuthorized = false
            return false
        }
    }

    // MARK: - Categories

    /// Registers notification categories with action buttons.
    func registerCategories() {
        let takenAction = UNNotificationAction(
            identifier: Self.takenActionId,
            title: "Taken",
            options: [.authenticationRequired]
        )
        let notYetAction = UNNotificationAction(
            identifier: Self.notYetActionId,
            title: "Not Yet",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionId,
            title: "Snooze",
            options: []
        )

        let medicationCategory = UNNotificationCategory(
            identifier: Self.medicationCategoryId,
            actions: [takenAction, notYetAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([medicationCategory])
        print("[NotificationService] Registered medication reminder category")
    }

    // MARK: - Schedule / Cancel

    /// Schedules a local notification at the given time components.
    func scheduleNotification(
        id: String,
        title: String,
        body: String,
        at dateComponents: DateComponents,
        repeats: Bool = true,
        category: String? = nil,
        userInfo: [String: String] = [:]
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category = category {
            content.categoryIdentifier = category
        }
        // UNNotificationContent.userInfo expects [AnyHashable: Any]
        content.userInfo = userInfo

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
            print("[NotificationService] Scheduled \(id) at \(dateComponents)")
        } catch {
            print("[NotificationService] Failed to schedule \(id): \(error)")
        }
    }

    /// Schedules a one-shot notification after a delay.
    func scheduleNotificationAfter(
        id: String,
        title: String,
        body: String,
        delay: TimeInterval,
        category: String? = nil,
        userInfo: [String: String] = [:]
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category = category {
            content.categoryIdentifier = category
        }
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
            print("[NotificationService] Scheduled \(id) after \(delay)s")
        } catch {
            print("[NotificationService] Failed to schedule \(id): \(error)")
        }
    }

    /// Cancels a specific notification by ID.
    func cancelNotification(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        print("[NotificationService] Cancelled \(id)")
    }

    /// Cancels specific notifications by IDs.
    func cancelNotifications(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancels all pending notifications.
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        print("[NotificationService] Cancelled all")
    }

    /// Returns all currently pending notification requests.
    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}
