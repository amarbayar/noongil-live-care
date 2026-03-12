import Foundation

/// Manages caregiver invitations, linking, and relationship CRUD.
@MainActor
final class CaregiverService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var relationships: [CaregiverRelationship] = []
    @Published private(set) var invitations: [CaregiverInvitation] = []
    @Published private(set) var membersICareFor: [CaregiverMember] = []

    // MARK: - Dependencies

    private let userId: String
    private let storageService: StorageService?
    private let backendClient: BackendClient

    init(userId: String, storageService: StorageService? = nil, backendClient: BackendClient? = nil) {
        self.userId = userId
        self.storageService = storageService
        self.backendClient = backendClient ?? BackendClient()
    }

    // MARK: - Invitations

    /// Creates an email-targeted invitation via the backend API.
    /// Result type for invitation creation — surfaces errors to the UI.
    enum InviteResult {
        case success(CaregiverInvitation)
        case failure(String)
    }

    func createInvitation(caregiverEmail: String, permissions: [CaregiverPermission]) async -> InviteResult {
        struct Body: Encodable {
            let caregiverEmail: String
            let permissions: [String]
        }

        do {
            let invitation: CaregiverInvitation = try await backendClient.postAndDecode(
                "/api/caregiver/invitations",
                body: Body(
                    caregiverEmail: caregiverEmail,
                    permissions: permissions.map(\.rawValue)
                )
            )
            invitations.append(invitation)
            return .success(invitation)
        } catch {
            print("[CaregiverService] Error creating invitation: \(error)")
            return .failure(describeBackendError(error))
        }
    }

    /// Fetches pending/accepted invitations for this member.
    func fetchInvitations() async {
        struct Response: Decodable {
            let invitations: [CaregiverInvitation]
        }

        do {
            let response: Response = try await backendClient.get("/api/caregiver/invitations")
            invitations = response.invitations
        } catch {
            print("[CaregiverService] Error fetching invitations: \(error)")
        }
    }

    /// Revokes a pending invitation.
    func revokeInvitation(id: String) async {
        do {
            try await backendClient.delete("/api/caregiver/invitations/\(id)")
            invitations.removeAll { $0.id == id }
        } catch {
            print("[CaregiverService] Error revoking invitation: \(error)")
        }
    }

    // MARK: - Relationship Management

    /// Fetches all active caregiver relationships for this member.
    func fetchRelationships() async {
        do {
            struct Response: Decodable {
                let relationships: [CaregiverRelationship]
            }

            let response: Response = try await backendClient.get("/api/caregiver/relationships")
            relationships = response.relationships
        } catch {
            print("[CaregiverService] Error fetching relationships via backend: \(error)")

            guard let storage = storageService else { return }

            do {
                relationships = try await storage.fetchAll(
                    CaregiverRelationship.self,
                    from: "caregiver_relationships",
                    userId: userId,
                    limit: 20
                )
            } catch {
                print("[CaregiverService] Error fetching relationships via Firestore: \(error)")
            }
        }
    }

    /// Revokes a caregiver's access.
    func revokeRelationship(id: String) async {
        guard let index = relationships.firstIndex(where: { $0.id == id }) else { return }

        var relationship = relationships[index]
        relationship.status = .revoked
        relationship.revokedAt = Date()

        if let storage = storageService {
            do {
                _ = try await storage.save(
                    relationship,
                    to: "caregiver_relationships",
                    userId: userId,
                    documentId: id
                )
            } catch {
                print("[CaregiverService] Error revoking relationship: \(error)")
            }
        }

        relationships[index] = relationship
    }

    /// Returns only active relationships.
    var activeRelationships: [CaregiverRelationship] {
        relationships.filter { $0.status == .active }
    }

    // MARK: - Caregiver View (People I Care For)

    /// Fetches members this user is a caregiver for, via backend API.
    func fetchMembersICareFor() async {
        do {
            let response: MembersResponse = try await backendClient.get("/api/caregiver/members")
            membersICareFor = response.members
        } catch {
            print("[CaregiverService] Error fetching members I care for: \(error)")
        }
    }

    /// Fetches a member's reminders (meds + check-in schedule + custom) via backend API.
    func fetchMemberReminders(memberId: String) async -> MemberRemindersResponse? {
        do {
            let response: MemberRemindersResponse = try await backendClient.get(
                "/api/caregiver/members/\(memberId)/reminders"
            )
            return response
        } catch {
            print("[CaregiverService] Error fetching member reminders: \(error)")
            return nil
        }
    }

    /// Add a custom reminder for a member via backend API.
    func addReminderForMember(memberId: String, title: String, note: String?, schedule: [String]) async -> Bool {
        struct Body: Encodable {
            let title: String
            let note: String?
            let schedule: [String]
            let isEnabled: Bool
        }

        do {
            try await backendClient.post(
                "/api/caregiver/members/\(memberId)/reminders",
                body: Body(title: title, note: note, schedule: schedule, isEnabled: true)
            )
            return true
        } catch {
            print("[CaregiverService] Error adding reminder for member: \(error)")
            return false
        }
    }

    /// Delete a custom reminder for a member via backend API.
    func deleteReminderForMember(memberId: String, reminderId: String) async -> Bool {
        do {
            try await backendClient.delete(
                "/api/caregiver/members/\(memberId)/reminders/\(reminderId)"
            )
            return true
        } catch {
            print("[CaregiverService] Error deleting reminder for member: \(error)")
            return false
        }
    }
}

private func describeBackendError(_ error: Error) -> String {
    guard let backendError = error as? BackendClient.BackendError else {
        return error.localizedDescription
    }

    switch backendError {
    case .invalidResponse:
        return "The caregiver service returned an invalid response."
    case .apiError(let statusCode, let message):
        if statusCode == 401 {
            return "Your session expired. Please sign out and sign back in, then try again."
        }
        if statusCode == 403 {
            return "This caregiver action is not allowed for your account."
        }
        if statusCode == 502 {
            return "The invitation was created, but email delivery failed. Please try again."
        }
        return "Backend error (\(statusCode)): \(message)"
    }
}

// MARK: - API Response Types

struct CaregiverMember: Codable, Identifiable {
    var id: String { memberId }
    let memberId: String
    let memberName: String?
    let role: String
}

struct MembersResponse: Codable {
    let members: [CaregiverMember]
}

struct MemberRemindersResponse: Codable {
    let medications: [[String: AnyCodable]]
    let customReminders: [[String: AnyCodable]]
    let checkInSchedule: [String: AnyCodable]?
}

/// Lightweight type-erased Codable for JSON dictionaries from the API.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr.map(\.value) }
        else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        }
        else if container.decodeNil() { value = NSNull() }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let s = value as? String { try container.encode(s) }
        else if let i = value as? Int { try container.encode(i) }
        else if let d = value as? Double { try container.encode(d) }
        else if let b = value as? Bool { try container.encode(b) }
        else { try container.encodeNil() }
    }
}
