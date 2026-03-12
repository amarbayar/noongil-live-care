import Foundation
import FirebaseFirestore

/// A user-created or caregiver-created custom reminder (e.g. "Take a walk", "Drink water").
struct CustomReminder: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String              // member this belongs to
    var title: String
    var note: String?
    var schedule: [String]          // ["08:00", "14:00"]
    var isEnabled: Bool
    var createdBy: ReminderCreator
    let createdAt: Date

    init(
        userId: String,
        title: String,
        note: String? = nil,
        schedule: [String] = [],
        isEnabled: Bool = true,
        createdBy: ReminderCreator
    ) {
        self.userId = userId
        self.title = title
        self.note = note
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.createdBy = createdBy
        self.createdAt = Date()
    }
}

struct ReminderCreator: Codable {
    let userId: String
    let name: String?
    let role: CreatorRole
}

enum CreatorRole: String, Codable {
    case selfUser
    case caregiver
}
