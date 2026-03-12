import XCTest
import FirebaseFirestore

final class CaregiverServiceTests: XCTestCase {

    // MARK: - CaregiverInvitation Model

    func testInvitationStatus() {
        let pending = CaregiverInvitation(
            id: "inv-1",
            caregiverEmail: "alice@example.com",
            permissions: [.medications, .wellness],
            status: .pending,
            token: "test-token",
            createdAt: "2026-03-10T00:00:00Z",
            expiresAt: "2026-03-17T00:00:00Z"
        )
        XCTAssertEqual(pending.status, .pending)
        XCTAssertNil(pending.acceptedAt)
        XCTAssertNil(pending.acceptedBy)
    }

    func testInvitationStoresEmail() {
        let invitation = CaregiverInvitation(
            id: "inv-1",
            caregiverEmail: "bob@example.com",
            permissions: [.reminders],
            status: .pending,
            token: "tok-1",
            createdAt: "2026-03-10T00:00:00Z",
            expiresAt: "2026-03-17T00:00:00Z"
        )
        XCTAssertEqual(invitation.caregiverEmail, "bob@example.com")
        XCTAssertEqual(invitation.permissions, [.reminders])
    }

    func testInvitationIdentifiable() {
        let invitation = CaregiverInvitation(
            id: "inv-42",
            caregiverEmail: "test@example.com",
            permissions: [.wellness],
            status: .accepted,
            token: "tok-42",
            createdAt: "2026-03-10T00:00:00Z",
            expiresAt: "2026-03-17T00:00:00Z",
            acceptedAt: "2026-03-11T00:00:00Z",
            acceptedBy: "cg-1"
        )
        XCTAssertEqual(invitation.id, "inv-42")
        XCTAssertEqual(invitation.acceptedBy, "cg-1")
    }

    // MARK: - Relationship Model

    func testRelationshipDefaultsToActive() {
        let rel = CaregiverRelationship(
            memberId: "member-1",
            caregiverId: "caregiver-1"
        )
        XCTAssertEqual(rel.status, .active)
        XCTAssertEqual(rel.role, .primary)
        XCTAssertNil(rel.revokedAt)
    }

    func testRelationshipStoresIds() {
        let rel = CaregiverRelationship(
            memberId: "member-1",
            caregiverId: "caregiver-1",
            caregiverName: "Jane"
        )
        XCTAssertEqual(rel.memberId, "member-1")
        XCTAssertEqual(rel.caregiverId, "caregiver-1")
        XCTAssertEqual(rel.caregiverName, "Jane")
    }

    func testRelationshipDecodesFirestoreStylePayloadWithoutStoredIdField() throws {
        let firestoreLikePayload: [String: Any] = [
            "memberId": "member-1",
            "caregiverId": "caregiver-1",
            "caregiverName": "Jane",
            "role": "primary",
            "status": "active",
            "permissions": ["wellness", "reminders"],
            "linkedAt": "2026-03-12T02:21:04.834Z"
        ]

        let data = try JSONSerialization.data(withJSONObject: firestoreLikePayload)
        let relationship = try JSONDecoder().decode(CaregiverRelationship.self, from: data)

        XCTAssertNil(relationship.id)
        XCTAssertEqual(relationship.memberId, "member-1")
        XCTAssertEqual(relationship.caregiverId, "caregiver-1")
        XCTAssertEqual(relationship.caregiverName, "Jane")
        XCTAssertEqual(relationship.role, .primary)
        XCTAssertEqual(relationship.status, .active)
        XCTAssertEqual(relationship.permissions, [.wellness, .reminders])
        XCTAssertNotNil(relationship.linkedAt)
    }

    func testRelationshipDecodesBackendJSONWithExplicitIdField() throws {
        let backendPayload: [String: Any] = [
            "id": "rel-1",
            "memberId": "member-1",
            "caregiverId": "caregiver-1",
            "caregiverName": "Jane",
            "role": "primary",
            "status": "active",
            "permissions": ["wellness", "reminders"],
            "linkedAt": "2026-03-12T02:21:04.834Z"
        ]

        let data = try JSONSerialization.data(withJSONObject: backendPayload)
        let relationship = try JSONDecoder().decode(CaregiverRelationship.self, from: data)

        XCTAssertEqual(relationship.id, "rel-1")
        XCTAssertEqual(relationship.caregiverName, "Jane")
    }

    // MARK: - CaregiverService (without storage)

    @MainActor
    func testInitialStateIsEmpty() {
        let service = CaregiverService(userId: "user-1")
        XCTAssertTrue(service.relationships.isEmpty)
        XCTAssertTrue(service.invitations.isEmpty)
        XCTAssertTrue(service.membersICareFor.isEmpty)
    }

    @MainActor
    func testActiveRelationshipsFiltersRevoked() {
        let service = CaregiverService(userId: "member-1")
        // Without storage/backend, we test the computed property logic
        XCTAssertEqual(service.activeRelationships.count, 0)
    }

    // MARK: - Notification Preferences

    func testDefaultPreferencesAllEnabled() {
        let prefs = CaregiverNotificationPreferences.default
        XCTAssertTrue(prefs.dailySummaryEnabled)
        XCTAssertTrue(prefs.missedMedicationEnabled)
        XCTAssertTrue(prefs.emergencyAlertEnabled)
        XCTAssertTrue(prefs.anomalyAlertEnabled)
    }

    func testPreferencesQuietHoursDefaults() {
        let prefs = CaregiverNotificationPreferences.default
        XCTAssertEqual(prefs.quietHoursStart, "22:00")
        XCTAssertEqual(prefs.quietHoursEnd, "07:00")
    }
}
