import Foundation
import FirebaseFirestore

enum CompanionSessionEventType: String, Codable {
    case sessionStarted = "session_started"
    case userUtterance = "user_utterance"
    case assistantUtterance = "assistant_utterance"
    case creativeArtifactGenerated = "creative_artifact_generated"
    case sessionCompleted = "session_completed"
    case sessionAbandoned = "session_abandoned"
}

struct CompanionSessionEvent: Codable, Identifiable {
    @DocumentID var id: String?
    let sessionId: String
    let sequenceNumber: Int
    let type: CompanionSessionEventType
    let source: String
    let occurredAt: Date
    var text: String?
    var metadata: [String: String]?
    var evidenceRef: String?

    init(
        sessionId: String,
        sequenceNumber: Int,
        type: CompanionSessionEventType,
        source: String,
        occurredAt: Date = Date(),
        text: String? = nil,
        metadata: [String: String]? = nil,
        evidenceRef: String? = nil
    ) {
        self.sessionId = sessionId
        self.sequenceNumber = sequenceNumber
        self.type = type
        self.source = source
        self.occurredAt = occurredAt
        self.text = text
        self.metadata = metadata
        self.evidenceRef = evidenceRef
    }

    var documentId: String {
        id ?? "\(sessionId)_\(sequenceNumber)"
    }
}

enum CompanionProjectionKind: String, Codable, Hashable {
    case memoryProjection = "memory_projection"
    case graphSync = "graph_sync"
}

enum CompanionProjectionStatus: String, Codable {
    case pending
    case completed
    case failed
}

struct CompanionProjectionOutboxItem: Codable, Identifiable {
    @DocumentID var id: String?
    let sessionId: String
    let kind: CompanionProjectionKind
    var status: CompanionProjectionStatus
    let createdAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastError: String?
    var evidenceRef: String?
    var payloadJSON: String?
    var receiptId: String?
    var completedAt: Date?

    init(
        sessionId: String,
        kind: CompanionProjectionKind,
        status: CompanionProjectionStatus = .pending,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil,
        evidenceRef: String? = nil,
        payloadJSON: String? = nil,
        receiptId: String? = nil,
        completedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.evidenceRef = evidenceRef
        self.payloadJSON = payloadJSON
        self.receiptId = receiptId
        self.completedAt = completedAt
    }

    var documentId: String {
        id ?? "\(sessionId)_\(kind.rawValue)"
    }
}
