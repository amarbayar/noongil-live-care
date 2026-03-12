import Foundation
import CryptoKit
import FirebaseFirestore

// MARK: - Transcript Entry

enum TranscriptRole: String, Codable {
    case user
    case assistant
    case system
}

struct TranscriptEntry: Codable {
    let role: TranscriptRole
    let text: String
    let timestamp: Date
}

// MARK: - Transcript

/// Full conversation transcript for a check-in. Stored separately at /users/{userId}/transcripts/{id}.
struct Transcript: Codable, Identifiable {
    @DocumentID var id: String?
    let checkInId: String
    var entries: [TranscriptEntry]
    var entryCount: Int
    let language: String
    let createdAt: Date

    init(checkInId: String, language: String = "en") {
        self.checkInId = checkInId
        self.entries = []
        self.entryCount = 0
        self.language = language
        self.createdAt = Date()
    }

    mutating func addEntry(role: TranscriptRole, text: String) {
        let entry = TranscriptEntry(role: role, text: text, timestamp: Date())
        entries.append(entry)
        entryCount = entries.count
    }

    // MARK: - Field Encryption

    mutating func encryptFields(using enc: EncryptionService, key: SymmetricKey) throws {
        for i in entries.indices {
            entries[i] = TranscriptEntry(
                role: entries[i].role,
                text: try enc.encryptString(entries[i].text, with: key),
                timestamp: entries[i].timestamp
            )
        }
    }

    mutating func decryptFields(using enc: EncryptionService, key: SymmetricKey) throws {
        for i in entries.indices {
            entries[i] = TranscriptEntry(
                role: entries[i].role,
                text: try enc.decryptString(entries[i].text, with: key),
                timestamp: entries[i].timestamp
            )
        }
    }
}
