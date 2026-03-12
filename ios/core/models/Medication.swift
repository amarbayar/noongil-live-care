import Foundation
import CryptoKit
import FirebaseFirestore

/// A user's medication. Name and dosage are encrypted at rest.
struct Medication: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var name: String               // encrypted
    var dosage: String?            // encrypted
    var form: String?              // "pill", "injection", "patch"
    var schedule: [String]         // ["08:00", "20:00"]
    var isActive: Bool
    var reminderEnabled: Bool
    let createdAt: Date

    init(
        userId: String,
        name: String,
        dosage: String? = nil,
        form: String? = nil,
        schedule: [String] = [],
        reminderEnabled: Bool = false
    ) {
        self.userId = userId
        self.name = name
        self.dosage = dosage
        self.form = form
        self.schedule = schedule
        self.isActive = true
        self.reminderEnabled = reminderEnabled
        self.createdAt = Date()
    }

    // MARK: - Field Encryption

    mutating func encryptFields(using enc: EncryptionService, key: SymmetricKey) throws {
        name = try enc.encryptString(name, with: key)
        if let d = dosage { dosage = try enc.encryptString(d, with: key) }
    }

    mutating func decryptFields(using enc: EncryptionService, key: SymmetricKey) throws {
        name = try enc.decryptString(name, with: key)
        if let d = dosage { dosage = try enc.decryptString(d, with: key) }
    }
}
