import Foundation
import CryptoKit
import FirebaseFirestore

// MARK: - Check-In Types

enum CheckInType: String, Codable {
    case morning
    case evening
    case adhoc
}

enum CheckInStatus: String, Codable {
    case inProgress
    case completed
    case abandoned
}

// MARK: - CheckIn

struct CheckIn: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let type: CheckInType
    var startedAt: Date
    var completedAt: Date?
    var completionStatus: CheckInStatus
    var durationSeconds: Int?
    var pipelineMode: String?
    var inputMethod: String?

    // Extracted health data (all optional — progressive extraction)
    var mood: MoodEntry?
    var sleep: SleepEntry?
    var symptoms: [SymptomEntry]
    var medicationAdherence: [MedicationAdherenceEntry]

    // AI-generated summary (encrypted at rest)
    var aiSummary: String?

    var checkInNumber: Int?
    let createdAt: Date

    init(
        userId: String,
        type: CheckInType,
        inputMethod: String? = "voice",
        pipelineMode: String? = nil
    ) {
        self.userId = userId
        self.type = type
        self.startedAt = Date()
        self.completionStatus = .inProgress
        self.pipelineMode = pipelineMode
        self.inputMethod = inputMethod
        self.symptoms = []
        self.medicationAdherence = []
        self.createdAt = Date()
    }

    // MARK: - Field Encryption

    mutating func encryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let s = aiSummary { aiSummary = try enc.encryptString(s, with: key) }
        try mood?.encryptFields(using: enc, key: key)
        try sleep?.encryptFields(using: enc, key: key)
        for i in symptoms.indices { try symptoms[i].encryptFields(using: enc, key: key) }
        for i in medicationAdherence.indices { try medicationAdherence[i].encryptFields(using: enc, key: key) }
    }

    mutating func decryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let s = aiSummary { aiSummary = try enc.decryptString(s, with: key) }
        try mood?.decryptFields(using: enc, key: key)
        try sleep?.decryptFields(using: enc, key: key)
        for i in symptoms.indices { try symptoms[i].decryptFields(using: enc, key: key) }
        for i in medicationAdherence.indices { try medicationAdherence[i].decryptFields(using: enc, key: key) }
    }
}
