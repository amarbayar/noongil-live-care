import Foundation
import FirebaseFirestore

// MARK: - Relationship

enum CaregiverRole: String, Codable {
    case primary    // main caregiver (spouse, partner, child)
    case secondary  // additional caregiver (sibling, friend, aide)
}

enum RelationshipStatus: String, Codable {
    case pending    // invite sent, not yet accepted
    case active     // linked and active
    case revoked    // member revoked access
}

/// Data categories a caregiver may access. Defaults to all for backward compatibility.
enum CaregiverPermission: String, Codable, CaseIterable {
    case medications    // view active medications
    case reminders      // view and create custom reminders
    case schedule       // view check-in schedule
    case wellness       // view wellness dashboard

    var displayName: String {
        switch self {
        case .medications: return "Medications"
        case .reminders: return "Custom Reminders"
        case .schedule: return "Check-in Schedule"
        case .wellness: return "View Wellness Dashboard"
        }
    }
}

// MARK: - Invitation

enum InvitationStatus: String, Codable {
    case pending
    case accepted
    case revoked
    case expired
}

struct CaregiverInvitation: Codable, Identifiable {
    var id: String?
    let caregiverEmail: String
    let permissions: [CaregiverPermission]
    let status: InvitationStatus
    let token: String
    let createdAt: String
    let expiresAt: String
    let inviteURL: String?
    let emailDeliveryStatus: String?
    var acceptedAt: String?
    var acceptedBy: String?

    init(
        id: String? = nil,
        caregiverEmail: String,
        permissions: [CaregiverPermission],
        status: InvitationStatus,
        token: String,
        createdAt: String,
        expiresAt: String,
        inviteURL: String? = nil,
        emailDeliveryStatus: String? = nil,
        acceptedAt: String? = nil,
        acceptedBy: String? = nil
    ) {
        self.id = id
        self.caregiverEmail = caregiverEmail
        self.permissions = permissions
        self.status = status
        self.token = token
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.inviteURL = inviteURL
        self.emailDeliveryStatus = emailDeliveryStatus
        self.acceptedAt = acceptedAt
        self.acceptedBy = acceptedBy
    }
}

struct CaregiverRelationship: Codable, Identifiable {
    @DocumentID var id: String?
    let memberId: String             // the user being cared for
    let caregiverId: String          // the caregiver's userId
    var caregiverName: String?       // display name
    var role: CaregiverRole
    var status: RelationshipStatus
    var permissions: [CaregiverPermission]
    let linkedAt: Date
    var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case memberId
        case caregiverId
        case caregiverName
        case role
        case status
        case permissions
        case linkedAt
        case revokedAt
    }

    init(
        memberId: String,
        caregiverId: String,
        caregiverName: String? = nil,
        role: CaregiverRole = .primary,
        permissions: [CaregiverPermission] = CaregiverPermission.allCases.map { $0 }
    ) {
        self.memberId = memberId
        self.caregiverId = caregiverId
        self.caregiverName = caregiverName
        self.role = role
        self.status = .active
        self.permissions = permissions
        self.linkedAt = Date()
    }

    // Custom decoder: defaults permissions to all when field is missing (backward compat)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try Self.decodeDocumentID(from: decoder, container: container)
        memberId = try container.decode(String.self, forKey: .memberId)
        caregiverId = try container.decode(String.self, forKey: .caregiverId)
        caregiverName = try container.decodeIfPresent(String.self, forKey: .caregiverName)
        role = try container.decode(CaregiverRole.self, forKey: .role)
        status = try container.decode(RelationshipStatus.self, forKey: .status)
        permissions = try container.decodeIfPresent([CaregiverPermission].self, forKey: .permissions)
            ?? CaregiverPermission.allCases.map { $0 }
        linkedAt = try Self.decodeDate(forKey: .linkedAt, from: container)
        revokedAt = try Self.decodeOptionalDate(forKey: .revokedAt, from: container)
    }

    // Custom encoder: omit Firestore's @DocumentID wrapper for plain JSON encoding.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(memberId, forKey: .memberId)
        try container.encode(caregiverId, forKey: .caregiverId)
        try container.encodeIfPresent(caregiverName, forKey: .caregiverName)
        try container.encode(role, forKey: .role)
        try container.encode(status, forKey: .status)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(linkedAt, forKey: .linkedAt)
        try container.encodeIfPresent(revokedAt, forKey: .revokedAt)
    }

    private static func decodeDate(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        let isoString = try container.decode(String.self, forKey: key)
        if let parsed = parseISO8601Date(isoString) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unsupported date value: \(isoString)"
        )
    }

    private static func decodeOptionalDate(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let isoString = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseISO8601Date(isoString)
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    private static func decodeDocumentID(
        from decoder: Decoder,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> DocumentID<String> {
        if let firestoreDocumentID = try? DocumentID<String>(from: decoder) {
            return firestoreDocumentID
        }

        let explicitID = try container.decodeIfPresent(String.self, forKey: .id)
        return DocumentID<String>(wrappedValue: explicitID)
    }
}

// MARK: - Notification Preferences

struct CaregiverNotificationPreferences: Codable {
    var dailySummaryEnabled: Bool = true
    var missedMedicationEnabled: Bool = true
    var emergencyAlertEnabled: Bool = true
    var anomalyAlertEnabled: Bool = true
    var quietHoursStart: String? = "22:00"   // no notifications after this
    var quietHoursEnd: String? = "07:00"     // resume after this

    static let `default` = CaregiverNotificationPreferences()
}
