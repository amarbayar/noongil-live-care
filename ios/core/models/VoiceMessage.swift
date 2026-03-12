import Foundation
import FirebaseFirestore

struct VoiceMessage: Codable, Identifiable {
    @DocumentID var id: String?
    let caregiverId: String
    let caregiverName: String?
    let audioBase64: String
    let mimeType: String
    let durationSeconds: Double
    let transcript: String?
    var status: String
    let createdAt: String
    var listenedAt: String?

    var isUnread: Bool {
        status == "unread"
    }
}
