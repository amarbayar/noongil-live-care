import XCTest
import CryptoKit

@MainActor
final class FieldEncryptionTests: XCTestCase {

    private var encryption: EncryptionService!
    private var key: SymmetricKey!

    override func setUp() {
        super.setUp()
        encryption = EncryptionService(keychain: MockKeychainStorage())
        key = SymmetricKey(size: .bits256)
    }

    // MARK: - CheckIn Encryption

    func testCheckInEncryptsAndDecryptsSensitiveFields() throws {
        var checkIn = CheckIn(userId: "user1", type: .morning)
        checkIn.aiSummary = "Mood was low, tremor severity 4/5"
        checkIn.mood = MoodEntry(score: 3, description: "feeling shaky today", label: "negative")
        checkIn.sleep = SleepEntry(hours: 6, quality: 2, interruptions: 3, description: "woke up multiple times due to pain")
        checkIn.symptoms = [
            SymptomEntry(type: .tremor, severity: 4, location: "right hand", duration: "all day",
                         userDescription: "much worse after meals", comparedToYesterday: "worse")
        ]
        checkIn.medicationAdherence = [
            MedicationAdherenceEntry(medicationId: "med1", medicationName: "Levodopa",
                                     status: .taken, scheduledTime: "08:00", takenAt: Date(), reportedVia: "voice")
        ]

        // Encrypt
        var encrypted = checkIn
        try encrypted.encryptFields(using: encryption, key: key)

        // Verify encrypted fields are NOT readable
        XCTAssertNotEqual(encrypted.aiSummary, checkIn.aiSummary)
        XCTAssertNotEqual(encrypted.mood?.description, checkIn.mood?.description)
        XCTAssertNotEqual(encrypted.sleep?.description, checkIn.sleep?.description)
        XCTAssertNotEqual(encrypted.symptoms.first?.userDescription, checkIn.symptoms.first?.userDescription)
        XCTAssertNotEqual(encrypted.medicationAdherence.first?.medicationName, checkIn.medicationAdherence.first?.medicationName)

        // Non-sensitive fields remain unchanged
        XCTAssertEqual(encrypted.userId, "user1")
        XCTAssertEqual(encrypted.type, .morning)
        XCTAssertEqual(encrypted.mood?.score, 3)
        XCTAssertEqual(encrypted.sleep?.hours, 6)
        XCTAssertEqual(encrypted.symptoms.first?.severity, 4)
        XCTAssertEqual(encrypted.symptoms.first?.type, .tremor)

        // Decrypt
        var decrypted = encrypted
        try decrypted.decryptFields(using: encryption, key: key)

        // Verify decrypted fields match originals
        XCTAssertEqual(decrypted.aiSummary, "Mood was low, tremor severity 4/5")
        XCTAssertEqual(decrypted.mood?.description, "feeling shaky today")
        XCTAssertEqual(decrypted.sleep?.description, "woke up multiple times due to pain")
        XCTAssertEqual(decrypted.symptoms.first?.userDescription, "much worse after meals")
        XCTAssertEqual(decrypted.medicationAdherence.first?.medicationName, "Levodopa")
    }

    func testCheckInHandlesNilFieldsGracefully() throws {
        var checkIn = CheckIn(userId: "user1", type: .adhoc)
        // All optional fields are nil — should not throw
        try checkIn.encryptFields(using: encryption, key: key)
        try checkIn.decryptFields(using: encryption, key: key)
    }

    // MARK: - Transcript Encryption

    func testTranscriptEncryptsAndDecryptsEntries() throws {
        var transcript = Transcript(checkInId: "checkin1")
        transcript.addEntry(role: .user, text: "My tremor is really bad today")
        transcript.addEntry(role: .assistant, text: "I'm sorry to hear that. How is your sleep?")
        transcript.addEntry(role: .user, text: "I only slept 4 hours")

        var encrypted = transcript
        try encrypted.encryptFields(using: encryption, key: key)

        // All entry texts should be encrypted
        for (i, entry) in encrypted.entries.enumerated() {
            XCTAssertNotEqual(entry.text, transcript.entries[i].text)
        }
        // Roles should remain unchanged
        XCTAssertEqual(encrypted.entries[0].role, .user)
        XCTAssertEqual(encrypted.entries[1].role, .assistant)

        var decrypted = encrypted
        try decrypted.decryptFields(using: encryption, key: key)

        XCTAssertEqual(decrypted.entries[0].text, "My tremor is really bad today")
        XCTAssertEqual(decrypted.entries[1].text, "I'm sorry to hear that. How is your sleep?")
        XCTAssertEqual(decrypted.entries[2].text, "I only slept 4 hours")
    }

    // MARK: - Medication Encryption

    func testMedicationEncryptsAndDecryptsNameAndDosage() throws {
        var medication = Medication(userId: "user1", name: "Levodopa/Carbidopa", dosage: "25/100mg")

        var encrypted = medication
        try encrypted.encryptFields(using: encryption, key: key)

        XCTAssertNotEqual(encrypted.name, "Levodopa/Carbidopa")
        XCTAssertNotEqual(encrypted.dosage, "25/100mg")
        XCTAssertEqual(encrypted.userId, "user1")

        var decrypted = encrypted
        try decrypted.decryptFields(using: encryption, key: key)

        XCTAssertEqual(decrypted.name, "Levodopa/Carbidopa")
        XCTAssertEqual(decrypted.dosage, "25/100mg")
    }

    func testMedicationHandlesNilDosage() throws {
        var medication = Medication(userId: "user1", name: "Vitamin D")

        try medication.encryptFields(using: encryption, key: key)
        XCTAssertNotEqual(medication.name, "Vitamin D")
        XCTAssertNil(medication.dosage) // Nil should remain nil

        try medication.decryptFields(using: encryption, key: key)
        XCTAssertEqual(medication.name, "Vitamin D")
    }
}
