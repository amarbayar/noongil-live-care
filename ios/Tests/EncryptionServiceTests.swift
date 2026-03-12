import XCTest
import CryptoKit

final class EncryptionServiceTests: XCTestCase {

    private var service: EncryptionService!
    private let testUserId = "test-user-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        service = EncryptionService(keychain: MockKeychainStorage())
    }

    override func tearDown() {
        service.deleteKey(for: testUserId)
        super.tearDown()
    }

    // MARK: - Key Generation

    func testGenerateAndStoreKeySucceeds() throws {
        let key = try service.generateAndStoreKey(for: testUserId)
        let keySize = key.withUnsafeBytes { $0.count }
        XCTAssertEqual(keySize, 32)
    }

    func testLoadKeyReturnsStoredKey() throws {
        let original = try service.generateAndStoreKey(for: testUserId)
        let loaded = try service.loadKey(for: testUserId)

        let originalData = original.withUnsafeBytes { Data($0) }
        let loadedData = loaded.withUnsafeBytes { Data($0) }
        XCTAssertEqual(originalData, loadedData)
    }

    func testLoadKeyThrowsWhenNotFound() {
        XCTAssertThrowsError(try service.loadKey(for: "nonexistent-user")) { error in
            guard let encError = error as? EncryptionService.EncryptionError else {
                XCTFail("Expected EncryptionError, got \(error)")
                return
            }
            if case .keyNotFound = encError { /* expected */ }
            else { XCTFail("Expected .keyNotFound, got \(encError)") }
        }
    }

    func testGetOrCreateKeyCreatesNewKey() throws {
        let key = try service.getOrCreateKey(for: testUserId)
        let keySize = key.withUnsafeBytes { $0.count }
        XCTAssertEqual(keySize, 32)
    }

    func testGetOrCreateKeyReturnsExistingKey() throws {
        let first = try service.getOrCreateKey(for: testUserId)
        let second = try service.getOrCreateKey(for: testUserId)

        let firstData = first.withUnsafeBytes { Data($0) }
        let secondData = second.withUnsafeBytes { Data($0) }
        XCTAssertEqual(firstData, secondData)
    }

    func testDeleteKeyRemovesFromKeychain() throws {
        _ = try service.generateAndStoreKey(for: testUserId)
        service.deleteKey(for: testUserId)
        XCTAssertThrowsError(try service.loadKey(for: testUserId))
    }

    // MARK: - Encrypt / Decrypt

    func testEncryptDecryptRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let original = "Hello, Noongil! This is sensitive health data."
        let originalData = Data(original.utf8)

        let encrypted = try service.encrypt(originalData, with: key)
        XCTAssertNotEqual(encrypted, originalData)

        let decrypted = try service.decrypt(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), original)
    }

    func testEncryptProducesDifferentOutputEachTime() throws {
        let key = SymmetricKey(size: .bits256)
        let data = Data("same input".utf8)

        let encrypted1 = try service.encrypt(data, with: key)
        let encrypted2 = try service.encrypt(data, with: key)

        // AES-GCM uses random nonce, so same plaintext → different ciphertext
        XCTAssertNotEqual(encrypted1, encrypted2)
    }

    func testDecryptWithWrongKeyFails() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let data = Data("secret".utf8)

        let encrypted = try service.encrypt(data, with: key1)

        XCTAssertThrowsError(try service.decrypt(encrypted, with: key2)) { error in
            guard let encError = error as? EncryptionService.EncryptionError else {
                XCTFail("Expected EncryptionError")
                return
            }
            if case .decryptionFailed = encError { /* expected */ }
            else { XCTFail("Expected .decryptionFailed, got \(encError)") }
        }
    }

    func testDecryptCorruptedDataFails() throws {
        let key = SymmetricKey(size: .bits256)
        let corrupted = Data(repeating: 0xFF, count: 50)

        XCTAssertThrowsError(try service.decrypt(corrupted, with: key))
    }

    // MARK: - String Convenience

    func testEncryptDecryptStringRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let original = "User mood: feeling good today, tremor was mild"

        let encrypted = try service.encryptString(original, with: key)
        XCTAssertNotNil(Data(base64Encoded: encrypted))
        XCTAssertNotEqual(encrypted, original)

        let decrypted = try service.decryptString(encrypted, with: key)
        XCTAssertEqual(decrypted, original)
    }

    func testDecryptStringWithInvalidBase64Fails() throws {
        let key = SymmetricKey(size: .bits256)

        XCTAssertThrowsError(try service.decryptString("not-valid-base64!!!", with: key)) { error in
            guard let encError = error as? EncryptionService.EncryptionError else {
                XCTFail("Expected EncryptionError")
                return
            }
            if case .invalidData = encError { /* expected */ }
            else { XCTFail("Expected .invalidData, got \(encError)") }
        }
    }

    func testEncryptEmptyString() throws {
        let key = SymmetricKey(size: .bits256)
        let encrypted = try service.encryptString("", with: key)
        let decrypted = try service.decryptString(encrypted, with: key)
        XCTAssertEqual(decrypted, "")
    }

    // MARK: - Keychain + Encrypt Integration

    func testKeychainKeyWorksForEncryption() throws {
        let key = try service.getOrCreateKey(for: testUserId)
        let original = "Integration test data"

        let encrypted = try service.encryptString(original, with: key)

        let loadedKey = try service.loadKey(for: testUserId)
        let decrypted = try service.decryptString(encrypted, with: loadedKey)

        XCTAssertEqual(decrypted, original)
    }
}
