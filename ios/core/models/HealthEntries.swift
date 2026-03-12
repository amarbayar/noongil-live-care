import Foundation
import CryptoKit

// MARK: - Mood

struct MoodEntry: Codable {
    var score: Int?             // 1-5
    var description: String?    // user's own words
    var label: String?          // "positive", "negative", "neutral"
}

// MARK: - Sleep

struct SleepEntry: Codable {
    var hours: Double?
    var quality: Int?           // 1-5
    var interruptions: Int?
    var description: String?    // user's own words
}

// MARK: - Symptoms

enum SymptomType: String, Codable {
    case tremor
    case rigidity
    case pain
    case fatigue
    case dizziness
    case nausea
    case headache
    case numbness
    case weakness
    case cramping
    case stiffness
    case balanceIssues
    case speechDifficulty
    case swallowingDifficulty
    case breathingDifficulty
    case other
}

struct SymptomEntry: Codable {
    var type: SymptomType
    var severity: Int?          // 1-5 (mapped from natural language)
    var location: String?
    var duration: String?
    var userDescription: String? // encrypted — user's own words
    var comparedToYesterday: String? // "better", "same", "worse"
}

// MARK: - Medication Adherence

enum MedicationStatus: String, Codable {
    case taken
    case missed
    case skipped
    case delayed
}

struct MedicationAdherenceEntry: Codable {
    var medicationId: String?
    var medicationName: String
    var status: MedicationStatus
    var scheduledTime: String?
    var takenAt: Date?
    var reportedVia: String?    // "voice", "manual"
}

// MARK: - Field Encryption Helpers

extension MoodEntry {
    mutating func encryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let d = description { description = try enc.encryptString(d, with: key) }
    }
    mutating func decryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let d = description { description = try enc.decryptString(d, with: key) }
    }
}

extension SleepEntry {
    mutating func encryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let d = description { description = try enc.encryptString(d, with: key) }
    }
    mutating func decryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let d = description { description = try enc.decryptString(d, with: key) }
    }
}

extension SymptomEntry {
    mutating func encryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let d = userDescription { userDescription = try enc.encryptString(d, with: key) }
    }
    mutating func decryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        if let d = userDescription { userDescription = try enc.decryptString(d, with: key) }
    }
}

extension MedicationAdherenceEntry {
    mutating func encryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        medicationName = try enc.encryptString(medicationName, with: key)
    }
    mutating func decryptFields(using enc: EncryptionService, key: CryptoKit.SymmetricKey) throws {
        medicationName = try enc.decryptString(medicationName, with: key)
    }
}
