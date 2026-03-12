import Foundation
import CryptoKit

struct CompanionMemoryProjectionPayload: Codable {
    struct Entry: Codable {
        let role: String
        let text: String
    }

    struct Artifact: Codable, Equatable {
        let mediaType: String
        let prompt: String
        let createdAt: Date

        init(mediaType: String, prompt: String, createdAt: Date = Date()) {
            self.mediaType = mediaType
            self.prompt = prompt
            self.createdAt = createdAt
        }
    }

    let sessionId: String
    let source: String
    let intent: String?
    let createdAt: Date
    let transcript: [Entry]
    let artifacts: [Artifact]
}

@MainActor
final class MemoryProjectionService {
    private let sessionStore: LiveCheckInSessionStore?
    private let storageService: StorageService?
    private let geminiService: GeminiService?
    private let userId: String?
    private var isDraining = false

    init(
        sessionStore: LiveCheckInSessionStore? = nil,
        storageService: StorageService? = nil,
        geminiService: GeminiService? = nil,
        userId: String? = nil
    ) {
        self.sessionStore = sessionStore
        self.storageService = storageService
        self.geminiService = geminiService
        self.userId = userId
    }

    func drainPendingMemoryProjections(using memoryService: MemoryService? = nil) async {
        guard !isDraining else { return }
        guard let sessionStore, let userId else { return }

        let resolvedMemoryService: MemoryService
        if let memoryService {
            resolvedMemoryService = memoryService
        } else {
            let createdMemoryService = MemoryService(
                storageService: storageService,
                geminiService: geminiService,
                userId: userId
            )
            await createdMemoryService.loadMemories()
            resolvedMemoryService = createdMemoryService
        }

        isDraining = true
        defer { isDraining = false }

        do {
            let outboxItems = try await sessionStore.loadOutboxItems(
                userId: userId,
                kind: .memoryProjection,
                statuses: Set([.pending, .failed])
            )

            for outboxItem in outboxItems {
                do {
                    let payload = try await loadPayload(for: outboxItem, userId: userId)
                    let transcript = materializedTranscript(from: payload)
                    let outcome = await resolvedMemoryService.extractProjectionOutcome(transcript: transcript)
                    let receiptId = Self.makeReceiptId(for: payload)

                    if let delta = outcome.delta {
                        await resolvedMemoryService.applyDelta(delta)
                    }
                    await resolvedMemoryService.consolidateMemories()

                    let status: CompanionProjectionStatus = outcome.shouldRetry ? .pending : .completed
                    let error = outcome.shouldRetry ? "Gemini memory extraction failed; will retry." : nil
                    await saveAttempt(
                        for: outboxItem,
                        userId: userId,
                        status: status,
                        error: error,
                        receiptId: outcome.shouldRetry ? nil : receiptId
                    )
                } catch {
                    await saveAttempt(
                        for: outboxItem,
                        userId: userId,
                        status: .pending,
                        error: error.localizedDescription,
                        receiptId: nil
                    )
                }
            }
        } catch {
            print("[MemoryProjectionService] Failed to load memory outbox: \(error)")
        }
    }

    static func makePayloadJSON(
        sessionId: String,
        source: String,
        intent: String?,
        transcript: [(role: String, text: String)],
        artifacts: [CompanionMemoryProjectionPayload.Artifact] = [],
        createdAt: Date = Date()
    ) -> String? {
        let payload = CompanionMemoryProjectionPayload(
            sessionId: sessionId,
            source: source,
            intent: intent,
            createdAt: createdAt,
            transcript: transcript.map {
                CompanionMemoryProjectionPayload.Entry(role: $0.role, text: $0.text)
            },
            artifacts: artifacts
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func loadPayload(
        for outboxItem: CompanionProjectionOutboxItem,
        userId: String
    ) async throws -> CompanionMemoryProjectionPayload {
        if let payloadJSON = outboxItem.payloadJSON {
            do {
                return try Self.decodePayload(from: payloadJSON)
            } catch {
                print("[MemoryProjectionService] Invalid payload JSON for session \(outboxItem.sessionId): \(error)")
            }
        }

        guard let sessionStore else {
            throw ProjectionError.missingPayload(outboxItem.sessionId)
        }

        let sessionEvents = try await sessionStore.loadSessionEvents(
            userId: userId,
            sessionId: outboxItem.sessionId
        )

        guard let payload = Self.makePayload(from: sessionEvents, sessionId: outboxItem.sessionId) else {
            throw ProjectionError.missingPayload(outboxItem.sessionId)
        }
        return payload
    }

    private func saveAttempt(
        for outboxItem: CompanionProjectionOutboxItem,
        userId: String,
        status: CompanionProjectionStatus,
        error: String?,
        receiptId: String?
    ) async {
        guard let sessionStore else { return }

        var updatedItem = outboxItem
        updatedItem.status = status
        updatedItem.attemptCount += 1
        updatedItem.lastAttemptAt = Date()
        updatedItem.lastError = error
        updatedItem.receiptId = receiptId
        updatedItem.completedAt = status == .completed ? Date() : nil

        do {
            _ = try await sessionStore.save(outboxItem: updatedItem, userId: userId)
        } catch {
            print("[MemoryProjectionService] Failed to save memory outbox state for session \(outboxItem.sessionId): \(error)")
        }
    }

    private static func decodePayload(from payloadJSON: String) throws -> CompanionMemoryProjectionPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(payloadJSON.utf8)
        return try decoder.decode(CompanionMemoryProjectionPayload.self, from: data)
    }

    private static func makePayload(
        from sessionEvents: [CompanionSessionEvent],
        sessionId: String
    ) -> CompanionMemoryProjectionPayload? {
        let transcript = sessionEvents.compactMap { event -> CompanionMemoryProjectionPayload.Entry? in
            switch event.type {
            case .userUtterance:
                guard let text = event.text else { return nil }
                return CompanionMemoryProjectionPayload.Entry(role: "user", text: text)
            case .assistantUtterance:
                guard let text = event.text else { return nil }
                return CompanionMemoryProjectionPayload.Entry(role: "assistant", text: text)
            default:
                return nil
            }
        }

        let artifacts = sessionEvents.compactMap { event -> CompanionMemoryProjectionPayload.Artifact? in
            guard event.type == .creativeArtifactGenerated,
                  let prompt = event.text,
                  let mediaType = event.metadata?["mediaType"] else {
                return nil
            }
            return CompanionMemoryProjectionPayload.Artifact(
                mediaType: mediaType,
                prompt: prompt,
                createdAt: event.occurredAt
            )
        }

        guard !transcript.isEmpty || !artifacts.isEmpty else { return nil }

        let startEvent = sessionEvents.first { $0.type == .sessionStarted }
        let source = startEvent?.source ?? sessionEvents.first?.source ?? "unknown"
        let intent = startEvent?.metadata?["intent"] ?? startEvent?.metadata?["checkInType"]
        let createdAt = sessionEvents.first?.occurredAt ?? Date()

        return CompanionMemoryProjectionPayload(
            sessionId: sessionId,
            source: source,
            intent: intent,
            createdAt: createdAt,
            transcript: transcript,
            artifacts: artifacts
        )
    }

    private func materializedTranscript(
        from payload: CompanionMemoryProjectionPayload
    ) -> [(role: String, text: String)] {
        var transcript = payload.transcript.map { (role: $0.role, text: $0.text) }
        transcript.append(contentsOf: payload.artifacts.map {
            (
                role: "user",
                text: "I created a \($0.mediaType) with prompt \($0.prompt)."
            )
        })
        return transcript
    }

    private static func makeReceiptId(for payload: CompanionMemoryProjectionPayload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(payload)) ?? Data(payload.sessionId.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(payload.sessionId):\(hex)"
    }
}

extension MemoryProjectionService {
    enum ProjectionError: LocalizedError {
        case missingPayload(String)

        var errorDescription: String? {
            switch self {
            case .missingPayload(let sessionId):
                return "Missing replayable memory payload for session \(sessionId)"
            }
        }
    }
}
