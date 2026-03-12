import XCTest

final class CaregiverPermissionTests: XCTestCase {

    // MARK: - Default Permissions

    func testDefaultPermissionsIncludeAll() {
        let relationship = CaregiverRelationship(
            memberId: "m1",
            caregiverId: "cg1"
        )
        XCTAssertEqual(
            Set(relationship.permissions),
            Set(CaregiverPermission.allCases),
            "Default should include all permissions"
        )
    }

    // MARK: - Custom Permissions

    func testCustomPermissions() {
        let relationship = CaregiverRelationship(
            memberId: "m1",
            caregiverId: "cg1",
            permissions: [.medications]
        )
        XCTAssertEqual(relationship.permissions, [.medications])
    }

    func testEmptyPermissions() {
        let relationship = CaregiverRelationship(
            memberId: "m1",
            caregiverId: "cg1",
            permissions: []
        )
        XCTAssertTrue(relationship.permissions.isEmpty)
    }

    // MARK: - Display Names

    func testPermissionDisplayNames() {
        XCTAssertEqual(CaregiverPermission.medications.displayName, "Medications")
        XCTAssertEqual(CaregiverPermission.reminders.displayName, "Custom Reminders")
        XCTAssertEqual(CaregiverPermission.schedule.displayName, "Check-in Schedule")
        XCTAssertEqual(CaregiverPermission.wellness.displayName, "View Wellness Dashboard")
    }

    // MARK: - CaseIterable

    func testAllCasesHasFourPermissions() {
        XCTAssertEqual(CaregiverPermission.allCases.count, 4)
    }

    // MARK: - CaregiverInvitation

    func testInvitationCodableRoundTrip() throws {
        let invitation = CaregiverInvitation(
            id: "inv-1",
            caregiverEmail: "alice@example.com",
            permissions: [.medications, .wellness],
            status: .pending,
            token: "test-token",
            createdAt: "2026-03-10T00:00:00Z",
            expiresAt: "2026-03-17T00:00:00Z"
        )
        let data = try JSONEncoder().encode(invitation)
        let decoded = try JSONDecoder().decode(CaregiverInvitation.self, from: data)
        XCTAssertEqual(decoded.caregiverEmail, "alice@example.com")
        XCTAssertEqual(decoded.permissions, [.medications, .wellness])
        XCTAssertEqual(decoded.status, .pending)
        XCTAssertEqual(decoded.token, "test-token")
    }

    // MARK: - Codable Round-Trip

    func testPermissionCodableRoundTrip() throws {
        let original: [CaregiverPermission] = [.medications, .schedule]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([CaregiverPermission].self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testRelationshipEncodesPermissions() throws {
        let relationship = CaregiverRelationship(
            memberId: "m1",
            caregiverId: "cg1",
            permissions: [.medications]
        )
        let data = try JSONEncoder().encode(relationship)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let perms = json?["permissions"] as? [String]
        XCTAssertEqual(perms, ["medications"])
    }
}
