import Foundation
import CryptoKit
import Security

// MARK: - KeychainStorage Protocol

/// Abstracts Keychain operations so EncryptionService can be tested with a mock.
protocol KeychainStorage {
    func store(data: Data, service: String, account: String) throws
    func load(service: String, account: String) throws -> Data
    func delete(service: String, account: String)
}

/// Real Keychain implementation using the Security framework.
final class SystemKeychainStorage: KeychainStorage {

    func store(data: Data, service: String, account: String) throws {
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionService.EncryptionError.keychainError(status)
        }
    }

    func load(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw EncryptionService.EncryptionError.keyNotFound
            }
            throw EncryptionService.EncryptionError.keychainError(status)
        }
        return data
    }

    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory mock for unit tests. No Keychain entitlements needed.
final class MockKeychainStorage: KeychainStorage {
    private var store_: [String: Data] = [:]

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }

    func store(data: Data, service: String, account: String) throws {
        store_[key(service: service, account: account)] = data
    }

    func load(service: String, account: String) throws -> Data {
        guard let data = store_[key(service: service, account: account)] else {
            throw EncryptionService.EncryptionError.keyNotFound
        }
        return data
    }

    func delete(service: String, account: String) {
        store_[key(service: service, account: account)] = nil
    }
}

/// AES-256-GCM field-level encryption with pluggable key storage.
final class EncryptionService {

    // MARK: - Errors

    enum EncryptionError: Error, LocalizedError {
        case keyNotFound
        case keychainError(OSStatus)
        case encryptionFailed
        case decryptionFailed
        case invalidData

        var errorDescription: String? {
            switch self {
            case .keyNotFound: return "Encryption key not found in Keychain"
            case .keychainError(let status): return "Keychain error: \(status)"
            case .encryptionFailed: return "Encryption failed"
            case .decryptionFailed: return "Decryption failed"
            case .invalidData: return "Invalid data format"
            }
        }
    }

    // MARK: - Key Storage

    private let keychain: KeychainStorage
    private let servicePrefix = "com.noongil.encryption"

    init(keychain: KeychainStorage = SystemKeychainStorage()) {
        self.keychain = keychain
    }

    private func keychainAccount(for userId: String) -> String {
        "\(servicePrefix).\(userId)"
    }

    /// Generates a new 256-bit symmetric key and stores it for the given user.
    func generateAndStoreKey(for userId: String) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try storeKey(key, for: userId)
        return key
    }

    /// Retrieves the user's encryption key, or generates one if none exists.
    func getOrCreateKey(for userId: String) throws -> SymmetricKey {
        if let existing = try? loadKey(for: userId) {
            return existing
        }
        return try generateAndStoreKey(for: userId)
    }

    /// Stores a symmetric key.
    func storeKey(_ key: SymmetricKey, for userId: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let account = keychainAccount(for: userId)
        try keychain.store(data: keyData, service: servicePrefix, account: account)
    }

    /// Loads a symmetric key.
    func loadKey(for userId: String) throws -> SymmetricKey {
        let account = keychainAccount(for: userId)
        let keyData = try keychain.load(service: servicePrefix, account: account)
        return SymmetricKey(data: keyData)
    }

    /// Deletes the encryption key for a user.
    func deleteKey(for userId: String) {
        let account = keychainAccount(for: userId)
        keychain.delete(service: servicePrefix, account: account)
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypts data using AES-256-GCM. Returns nonce + ciphertext + tag as combined data.
    func encrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }

    /// Decrypts AES-256-GCM combined data (nonce + ciphertext + tag).
    func decrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    // MARK: - String Convenience

    /// Encrypts a string and returns a Base64-encoded string (suitable for Firestore storage).
    func encryptString(_ string: String, with key: SymmetricKey) throws -> String {
        let data = Data(string.utf8)
        let encrypted = try encrypt(data, with: key)
        return encrypted.base64EncodedString()
    }

    /// Decrypts a Base64-encoded encrypted string.
    func decryptString(_ base64String: String, with key: SymmetricKey) throws -> String {
        guard let data = Data(base64Encoded: base64String) else {
            throw EncryptionError.invalidData
        }
        let decrypted = try decrypt(data, with: key)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        return string
    }
}
