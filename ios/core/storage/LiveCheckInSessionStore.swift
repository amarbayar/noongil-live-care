import Foundation
import FirebaseFirestore

enum LiveCheckInStartMode: Equatable {
    case new
    case resumed
}

struct LiveCheckInContext {
    let profile: UserProfile?
    let recentCheckIns: [CheckIn]
    let medications: [Medication]
    let vocabularyMap: VocabularyMap?
}

@MainActor
protocol LiveCheckInSessionStore: AnyObject {
    func loadContext(userId: String) async throws -> LiveCheckInContext
    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn?
    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript?
    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent]
    func loadOutboxItems(
        userId: String,
        kind: CompanionProjectionKind,
        statuses: Set<CompanionProjectionStatus>
    ) async throws -> [CompanionProjectionOutboxItem]
    func save(checkIn: CheckIn, userId: String) async throws -> String
    func save(transcript: Transcript, userId: String) async throws -> String
    func save(vocabularyMap: VocabularyMap, userId: String) async throws -> String
    func append(sessionEvent: CompanionSessionEvent, userId: String) async throws -> String
    func save(outboxItem: CompanionProjectionOutboxItem, userId: String) async throws -> String
    func markStartMode(_ mode: LiveCheckInStartMode)
}

extension LiveCheckInSessionStore {
    func loadOutboxItems(
        userId: String,
        kind: CompanionProjectionKind,
        statuses: Set<CompanionProjectionStatus>
    ) async throws -> [CompanionProjectionOutboxItem] {
        []
    }

    func markStartMode(_ mode: LiveCheckInStartMode) {}
}

@MainActor
final class FirestoreLiveCheckInSessionStore: LiveCheckInSessionStore {
    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    func loadContext(userId: String) async throws -> LiveCheckInContext {
        let profile = try await storageService.fetch(
            UserProfile.self,
            from: "profile",
            userId: userId,
            documentId: "main"
        )
        let medications = try await storageService.fetchAll(
            Medication.self,
            from: "medications",
            userId: userId
        )
        let vocabularyMap = try await storageService.fetch(
            VocabularyMap.self,
            from: "profile",
            userId: userId,
            documentId: "vocabulary"
        )

        let recentSnapshot = try await storageService.userCollection("checkins", userId: userId)
            .order(by: "startedAt", descending: true)
            .limit(to: 5)
            .getDocuments()
        let recentCheckIns = try recentSnapshot.documents.compactMap { doc in
            try doc.data(as: CheckIn.self)
        }

        return LiveCheckInContext(
            profile: profile,
            recentCheckIns: recentCheckIns,
            medications: medications,
            vocabularyMap: vocabularyMap
        )
    }

    func loadMostRecentInProgressCheckIn(userId: String, type: CheckInType) async throws -> CheckIn? {
        let snapshot = try await storageService.userCollection("checkins", userId: userId)
            .whereField("completionStatus", isEqualTo: CheckInStatus.inProgress.rawValue)
            .whereField("type", isEqualTo: type.rawValue)
            .order(by: "startedAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else { return nil }
        return try document.data(as: CheckIn.self)
    }

    func loadTranscript(userId: String, checkInId: String) async throws -> Transcript? {
        try await storageService.fetch(
            Transcript.self,
            from: "transcripts",
            userId: userId,
            documentId: checkInId
        )
    }

    func loadSessionEvents(userId: String, sessionId: String) async throws -> [CompanionSessionEvent] {
        let events = try await storageService.fetchAll(
            CompanionSessionEvent.self,
            from: "companionSessionEvents",
            userId: userId
        )
        return events
            .filter { $0.sessionId == sessionId }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    func save(checkIn: CheckIn, userId: String) async throws -> String {
        try await storageService.save(
            checkIn,
            to: "checkins",
            userId: userId,
            documentId: checkIn.id
        )
    }

    func save(transcript: Transcript, userId: String) async throws -> String {
        try await storageService.save(
            transcript,
            to: "transcripts",
            userId: userId,
            documentId: transcript.id ?? transcript.checkInId
        )
    }

    func save(vocabularyMap: VocabularyMap, userId: String) async throws -> String {
        try await storageService.save(
            vocabularyMap,
            to: "profile",
            userId: userId,
            documentId: "vocabulary"
        )
    }

    func append(sessionEvent: CompanionSessionEvent, userId: String) async throws -> String {
        try await storageService.save(
            sessionEvent,
            to: "companionSessionEvents",
            userId: userId,
            documentId: sessionEvent.documentId
        )
    }

    func loadOutboxItems(
        userId: String,
        kind: CompanionProjectionKind,
        statuses: Set<CompanionProjectionStatus>
    ) async throws -> [CompanionProjectionOutboxItem] {
        let items = try await storageService.fetchAll(
            CompanionProjectionOutboxItem.self,
            from: "companionProjectionOutbox",
            userId: userId
        )
        return items
            .filter { $0.kind == kind && statuses.contains($0.status) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.documentId < rhs.documentId
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func save(outboxItem: CompanionProjectionOutboxItem, userId: String) async throws -> String {
        try await storageService.save(
            outboxItem,
            to: "companionProjectionOutbox",
            userId: userId,
            documentId: outboxItem.documentId
        )
    }
}
