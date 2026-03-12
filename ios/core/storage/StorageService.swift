import Foundation
import FirebaseFirestore

/// Firestore wrapper with offline persistence and optional field-level encryption.
@MainActor
final class StorageService: ObservableObject {

    // MARK: - State

    @Published var isReady: Bool = false

    // MARK: - Dependencies

    private let db: Firestore
    private let encryption: EncryptionService

    // MARK: - Init

    init(encryption: EncryptionService = EncryptionService()) {
        self.encryption = encryption

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024 as NSNumber)
        let firestore = Firestore.firestore()
        firestore.settings = settings
        self.db = firestore
        self.isReady = true

        print("[StorageService] Initialized with offline persistence (100MB cache)")
    }

    // MARK: - Collection Path Builder

    /// Builds a Firestore document path: /users/{userId}/{collection}
    func userCollection(_ collection: String, userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection(collection)
    }

    /// Direct reference to the user document: /users/{userId}
    func userDocument(userId: String) -> DocumentReference {
        db.collection("users").document(userId)
    }

    // MARK: - CRUD Operations

    /// Saves a Codable object to Firestore. Generates a document ID if none provided.
    func save<T: Encodable>(
        _ object: T,
        to collection: String,
        userId: String,
        documentId: String? = nil
    ) async throws -> String {
        let collectionRef = userCollection(collection, userId: userId)
        let docRef = documentId.map { collectionRef.document($0) } ?? collectionRef.document()

        try docRef.setData(from: object, merge: true)
        print("[StorageService] Saved to \(collection)/\(docRef.documentID)")
        return docRef.documentID
    }

    /// Fetches a single document by ID and decodes it.
    func fetch<T: Decodable>(
        _ type: T.Type,
        from collection: String,
        userId: String,
        documentId: String
    ) async throws -> T? {
        let docRef = userCollection(collection, userId: userId).document(documentId)
        let snapshot = try await docRef.getDocument()

        guard snapshot.exists else { return nil }
        return try snapshot.data(as: type)
    }

    /// Fetches all documents in a collection, decoded to the given type.
    func fetchAll<T: Decodable>(
        _ type: T.Type,
        from collection: String,
        userId: String,
        limit: Int? = nil
    ) async throws -> [T] {
        var query: Query = userCollection(collection, userId: userId)
        if let limit = limit {
            query = query.limit(to: limit)
        }

        let snapshot: QuerySnapshot
        do {
            snapshot = try await query.getDocuments(source: .server)
        } catch {
            // Offline fallback — use cache
            snapshot = try await query.getDocuments(source: .cache)
        }
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: type)
        }
    }

    /// Deletes a document by ID.
    func delete(
        from collection: String,
        userId: String,
        documentId: String
    ) async throws {
        let docRef = userCollection(collection, userId: userId).document(documentId)
        try await docRef.delete()
        print("[StorageService] Deleted \(collection)/\(documentId)")
    }

    /// Observes a collection in real-time. Returns a listener registration for cleanup.
    func observe<T: Decodable>(
        _ type: T.Type,
        in collection: String,
        userId: String,
        onChange: @escaping ([T]) -> Void
    ) -> ListenerRegistration {
        let collectionRef = userCollection(collection, userId: userId)

        return collectionRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("[StorageService] Observe error: \(error)")
                return
            }

            guard let snapshot = snapshot else { return }
            let items = snapshot.documents.compactMap { doc in
                try? doc.data(as: type)
            }
            onChange(items)
        }
    }

    // MARK: - Encryption Access

    /// Exposes the encryption service for model-level field encryption.
    nonisolated var encryptionService: EncryptionService { encryption }

    // MARK: - Encrypted Field Helpers

    /// Saves a Codable object with specified fields encrypted.
    /// Encrypts field values before saving to Firestore.
    func saveEncrypted(
        _ fields: [String: String],
        to collection: String,
        userId: String,
        documentId: String? = nil,
        encryptedFieldNames: Set<String>
    ) async throws -> String {
        let key = try encryption.getOrCreateKey(for: userId)
        var processedFields: [String: String] = [:]

        for (fieldName, value) in fields {
            if encryptedFieldNames.contains(fieldName) {
                processedFields[fieldName] = try encryption.encryptString(value, with: key)
            } else {
                processedFields[fieldName] = value
            }
        }

        let collectionRef = userCollection(collection, userId: userId)
        let docRef = documentId.map { collectionRef.document($0) } ?? collectionRef.document()
        try await docRef.setData(processedFields, merge: true)

        print("[StorageService] Saved encrypted fields to \(collection)/\(docRef.documentID)")
        return docRef.documentID
    }

    /// Fetches and decrypts specified fields from a document.
    func fetchDecrypted(
        from collection: String,
        userId: String,
        documentId: String,
        encryptedFieldNames: Set<String>
    ) async throws -> [String: String]? {
        let docRef = userCollection(collection, userId: userId).document(documentId)
        let snapshot = try await docRef.getDocument()

        guard snapshot.exists, let data = snapshot.data() else { return nil }

        let key = try encryption.getOrCreateKey(for: userId)
        var result: [String: String] = [:]

        for (fieldName, value) in data {
            guard let stringValue = value as? String else { continue }
            if encryptedFieldNames.contains(fieldName) {
                result[fieldName] = try encryption.decryptString(stringValue, with: key)
            } else {
                result[fieldName] = stringValue
            }
        }

        return result
    }
}
