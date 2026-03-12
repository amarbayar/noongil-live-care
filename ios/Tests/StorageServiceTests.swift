import XCTest

/// StorageService tests that verify initialization and path building.
/// Full Firestore CRUD tests require a running Firebase emulator or live project.
@MainActor
final class StorageServiceTests: XCTestCase {

    func testEncryptionServiceRoundtripIntegration() throws {
        let encryption = EncryptionService(keychain: MockKeychainStorage())
        let userId = "test-storage-\(UUID().uuidString)"

        defer { encryption.deleteKey(for: userId) }

        let key = try encryption.getOrCreateKey(for: userId)

        let fields: [String: String] = [
            "mood": "feeling great",
            "notes": "Tremor was mild today",
            "date": "2026-02-24"
        ]
        let encryptedFieldNames: Set<String> = ["mood", "notes"]

        // Simulate the encrypt-before-save pattern
        var processedFields: [String: String] = [:]
        for (fieldName, value) in fields {
            if encryptedFieldNames.contains(fieldName) {
                processedFields[fieldName] = try encryption.encryptString(value, with: key)
            } else {
                processedFields[fieldName] = value
            }
        }

        // Encrypted fields should differ from originals
        XCTAssertNotEqual(processedFields["mood"], fields["mood"])
        XCTAssertNotEqual(processedFields["notes"], fields["notes"])
        // Non-encrypted fields should be unchanged
        XCTAssertEqual(processedFields["date"], fields["date"])

        // Simulate the decrypt-after-fetch pattern
        var decryptedFields: [String: String] = [:]
        for (fieldName, value) in processedFields {
            if encryptedFieldNames.contains(fieldName) {
                decryptedFields[fieldName] = try encryption.decryptString(value, with: key)
            } else {
                decryptedFields[fieldName] = value
            }
        }

        XCTAssertEqual(decryptedFields["mood"], "feeling great")
        XCTAssertEqual(decryptedFields["notes"], "Tremor was mild today")
        XCTAssertEqual(decryptedFields["date"], "2026-02-24")
    }

    func testDifferentUsersGetDifferentKeys() throws {
        let encryption = EncryptionService(keychain: MockKeychainStorage())
        let userId1 = "test-user1-\(UUID().uuidString)"
        let userId2 = "test-user2-\(UUID().uuidString)"

        defer {
            encryption.deleteKey(for: userId1)
            encryption.deleteKey(for: userId2)
        }

        let key1 = try encryption.getOrCreateKey(for: userId1)
        let key2 = try encryption.getOrCreateKey(for: userId2)

        let key1Data = key1.withUnsafeBytes { Data($0) }
        let key2Data = key2.withUnsafeBytes { Data($0) }

        XCTAssertNotEqual(key1Data, key2Data)
    }

    func testCrossUserDecryptionFails() throws {
        let encryption = EncryptionService(keychain: MockKeychainStorage())
        let userId1 = "test-cross1-\(UUID().uuidString)"
        let userId2 = "test-cross2-\(UUID().uuidString)"

        defer {
            encryption.deleteKey(for: userId1)
            encryption.deleteKey(for: userId2)
        }

        let key1 = try encryption.getOrCreateKey(for: userId1)
        let key2 = try encryption.getOrCreateKey(for: userId2)

        let encrypted = try encryption.encryptString("sensitive data", with: key1)

        // Decrypting with a different user's key should fail
        XCTAssertThrowsError(try encryption.decryptString(encrypted, with: key2))
    }
}
