import Foundation

/// Syncs completed check-ins + extraction results to the backend graph API.
/// Graph sync is persisted to a durable outbox before sending so the app can
/// retry later if the network or backend is unavailable.
@MainActor
final class GraphSyncService {
    private let client: BackendClient
    private let sessionStore: LiveCheckInSessionStore?
    private let userId: String?
    private var isDraining = false

    init(
        client: BackendClient = BackendClient(),
        sessionStore: LiveCheckInSessionStore? = nil,
        userId: String? = nil
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.userId = userId
    }

    /// Converts a CheckIn + ExtractionResult into the backend ingest payload,
    /// persists it to the graph outbox, and attempts delivery immediately.
    func syncCheckIn(_ checkIn: CheckIn, extraction: ExtractionResult) async {
        let sessionId = Self.makeSessionId(for: checkIn)
        let eventId = Self.makeEventId(sessionId: sessionId)
        let payload = Self.makePayload(checkIn: checkIn, extraction: extraction, eventId: eventId)

        guard let outboxItem = Self.makeOutboxItem(
            sessionId: sessionId,
            payload: payload,
            evidenceRef: checkIn.id ?? sessionId
        ) else {
            print("[GraphSyncService] Failed to encode graph payload for session \(sessionId)")
            return
        }

        let resolvedUserId = userId ?? checkIn.userId

        do {
            if let sessionStore {
                _ = try await sessionStore.save(outboxItem: outboxItem, userId: resolvedUserId)
            }
            await deliver(payload: payload, outboxItem: outboxItem, userId: resolvedUserId)
        } catch {
            print("[GraphSyncService] Failed to persist graph outbox for session \(sessionId): \(error)")
        }
    }

    /// Retries persisted graph sync outbox items for the configured user.
    func drainPendingGraphSyncs() async {
        guard !isDraining else { return }
        guard let sessionStore, let userId else { return }

        isDraining = true
        defer { isDraining = false }

        do {
            let outboxItems = try await sessionStore.loadOutboxItems(
                userId: userId,
                kind: .graphSync,
                statuses: Set([.pending, .failed])
            )

            for outboxItem in outboxItems {
                guard let payloadJSON = outboxItem.payloadJSON else {
                    await saveAttempt(
                        for: outboxItem,
                        userId: userId,
                        status: .pending,
                        error: "Missing graph payload JSON"
                    )
                    continue
                }

                do {
                    let payload = try Self.decodePayload(from: payloadJSON)
                    await deliver(payload: payload, outboxItem: outboxItem, userId: userId)
                } catch {
                    await saveAttempt(
                        for: outboxItem,
                        userId: userId,
                        status: .pending,
                        error: error.localizedDescription
                    )
                }
            }
        } catch {
            print("[GraphSyncService] Failed to load graph outbox: \(error)")
        }
    }

    // MARK: - Payload Construction

    static func makePayload(
        checkIn: CheckIn,
        extraction: ExtractionResult,
        eventId: String
    ) -> GraphIngestPayload {
        let completedAt = checkIn.completedAt ?? Date()
        let checkInId = resolvedCheckInId(for: checkIn, eventId: eventId)

        var mood: GraphIngestPayload.MoodPayload?
        if let m = checkIn.mood, let score = m.score {
            mood = GraphIngestPayload.MoodPayload(
                score: score,
                description: m.description
            )
        }

        var sleep: GraphIngestPayload.SleepPayload?
        if let s = checkIn.sleep, let hours = s.hours {
            sleep = GraphIngestPayload.SleepPayload(
                hours: hours,
                quality: s.quality,
                interruptions: s.interruptions
            )
        }

        let symptoms: [GraphIngestPayload.SymptomPayload]? = checkIn.symptoms.isEmpty ? nil :
            checkIn.symptoms.map { s in
                GraphIngestPayload.SymptomPayload(
                    type: s.type.rawValue,
                    severity: s.severity,
                    location: s.location,
                    duration: s.duration
                )
            }

        let medicationAdherence: [GraphIngestPayload.MedicationPayload]? =
            checkIn.medicationAdherence.isEmpty ? nil :
            checkIn.medicationAdherence.map { m in
                GraphIngestPayload.MedicationPayload(
                    medicationName: m.medicationName,
                    status: m.status.rawValue
                )
            }

        let triggers: [GraphIngestPayload.TriggerPayload]? = extraction.triggers?.map { t in
            GraphIngestPayload.TriggerPayload(name: t.name, type: t.type)
        }

        let activities: [GraphIngestPayload.ActivityPayload]? = extraction.activities?.map { a in
            GraphIngestPayload.ActivityPayload(name: a.name, duration: a.duration, intensity: a.intensity)
        }

        let concerns: [GraphIngestPayload.ConcernPayload]? = extraction.concerns?.map { c in
            GraphIngestPayload.ConcernPayload(text: c.text, theme: c.theme, urgency: c.urgency)
        }

        let iso8601 = ISO8601DateFormatter()
        let localDateFmt = DateFormatter()
        localDateFmt.dateFormat = "yyyy-MM-dd"
        localDateFmt.timeZone = .current
        let checkInPayload = GraphIngestPayload.CheckInPayload(
            id: checkInId,
            userId: checkIn.userId,
            type: checkIn.type.rawValue,
            completedAt: iso8601.string(from: completedAt),
            localDate: localDateFmt.string(from: completedAt),
            completionStatus: checkIn.completionStatus.rawValue,
            durationSeconds: checkIn.durationSeconds,
            mood: mood,
            sleep: sleep,
            symptoms: symptoms,
            medicationAdherence: medicationAdherence,
            triggers: triggers,
            activities: activities,
            concerns: concerns
        )

        return GraphIngestPayload(
            eventId: eventId,
            userId: checkIn.userId,
            checkIn: checkInPayload
        )
    }

    static func makePayloadJSON(
        checkIn: CheckIn,
        extraction: ExtractionResult,
        eventId: String
    ) -> String? {
        let payload = makePayload(checkIn: checkIn, extraction: extraction, eventId: eventId)
        return try? encodePayload(payload)
    }

    // MARK: - Delivery

    private func deliver(
        payload: GraphIngestPayload,
        outboxItem: CompanionProjectionOutboxItem,
        userId: String
    ) async {
        do {
            let _: GraphIngestAck = try await client.postAndDecode("/api/graph/ingest", body: payload)
            await saveAttempt(for: outboxItem, userId: userId, status: .completed, error: nil)
            print("[GraphSyncService] Synced check-in \(payload.checkIn.id)")
        } catch {
            await saveAttempt(
                for: outboxItem,
                userId: userId,
                status: .pending,
                error: error.localizedDescription
            )
            print("[GraphSyncService] Sync failed (will retry later): \(error)")
        }
    }

    private func saveAttempt(
        for outboxItem: CompanionProjectionOutboxItem,
        userId: String,
        status: CompanionProjectionStatus,
        error: String?
    ) async {
        guard let sessionStore else { return }

        var updatedItem = outboxItem
        updatedItem.status = status
        updatedItem.attemptCount += 1
        updatedItem.lastAttemptAt = Date()
        updatedItem.lastError = error

        do {
            _ = try await sessionStore.save(outboxItem: updatedItem, userId: userId)
        } catch {
            print("[GraphSyncService] Failed to save graph outbox state for session \(outboxItem.sessionId): \(error)")
        }
    }

    // MARK: - Helpers

    static func makeSessionId(for checkIn: CheckIn) -> String {
        checkIn.id ?? UUID().uuidString
    }

    static func makeEventId(sessionId: String) -> String {
        "\(sessionId)_graph_sync"
    }

    private static func makeOutboxItem(
        sessionId: String,
        payload: GraphIngestPayload,
        evidenceRef: String?
    ) -> CompanionProjectionOutboxItem? {
        guard let payloadJSON = try? encodePayload(payload) else { return nil }
        return CompanionProjectionOutboxItem(
            sessionId: sessionId,
            kind: .graphSync,
            evidenceRef: evidenceRef,
            payloadJSON: payloadJSON
        )
    }

    private static func resolvedCheckInId(for checkIn: CheckIn, eventId: String) -> String {
        if let id = checkIn.id, !id.isEmpty {
            return id
        }
        if eventId.hasSuffix("_graph_sync") {
            return String(eventId.dropLast("_graph_sync".count))
        }
        return UUID().uuidString
    }

    private static func encodePayload(_ payload: GraphIngestPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    private static func decodePayload(from payloadJSON: String) throws -> GraphIngestPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GraphIngestPayload.self, from: Data(payloadJSON.utf8))
    }
}

// MARK: - Backend Ack

private struct GraphIngestAck: Decodable {
    let status: String
    let eventId: String
    let duplicate: Bool
    let checkInId: String?
}

// MARK: - Payload Types (match backend zod schema)

struct GraphIngestPayload: Codable {
    let eventId: String
    let userId: String
    let checkIn: CheckInPayload

    struct CheckInPayload: Codable {
        let id: String
        let userId: String
        let type: String
        let completedAt: String
        let localDate: String?
        let completionStatus: String
        var durationSeconds: Int?
        var mood: MoodPayload?
        var sleep: SleepPayload?
        var symptoms: [SymptomPayload]?
        var medicationAdherence: [MedicationPayload]?
        var triggers: [TriggerPayload]?
        var activities: [ActivityPayload]?
        var concerns: [ConcernPayload]?
    }

    struct MoodPayload: Codable {
        let score: Int
        var description: String?
    }

    struct SleepPayload: Codable {
        let hours: Double
        var quality: Int?
        var interruptions: Int?
    }

    struct SymptomPayload: Codable {
        let type: String
        var severity: Int?
        var location: String?
        var duration: String?
    }

    struct MedicationPayload: Codable {
        let medicationName: String
        let status: String
    }

    struct TriggerPayload: Codable {
        let name: String
        var type: String?
    }

    struct ActivityPayload: Codable {
        let name: String
        var duration: String?
        var intensity: String?
    }

    struct ConcernPayload: Codable {
        let text: String
        var theme: String?
        var urgency: String?
    }
}
