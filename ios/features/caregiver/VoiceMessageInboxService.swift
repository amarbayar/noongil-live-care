import Foundation
import FirebaseFirestore

@MainActor
final class VoiceMessageInboxService: ObservableObject {
    @Published private(set) var messages: [VoiceMessage] = []

    private(set) var userId: String = ""
    private(set) var storageService: StorageService?
    private(set) var notificationService: NotificationService?

    private var listener: ListenerRegistration?
    private var hasLoadedInitialSnapshot = false
    private var knownUnreadIds: Set<String> = []

    func configure(
        userId: String,
        storageService: StorageService,
        notificationService: NotificationService
    ) {
        self.userId = userId
        self.storageService = storageService
        self.notificationService = notificationService
        startObserving()
    }

    func fetchMessages() async {
        guard let storage = storageService, !userId.isEmpty else { return }

        do {
            let fetched = try await storage.fetchAll(
                VoiceMessage.self,
                from: "voice_messages",
                userId: userId,
                limit: 50
            )
            messages = sortMessages(fetched)
            knownUnreadIds = Set(messages.compactMap { $0.isUnread ? $0.id : nil })
        } catch {
            print("[VoiceMessageInboxService] Failed to fetch messages: \(error)")
        }
    }

    func markAsListened(_ message: VoiceMessage) async {
        guard let storage = storageService, let id = message.id else { return }
        var updated = message
        updated.status = "listened"
        updated.listenedAt = ISO8601DateFormatter().string(from: Date())

        do {
            _ = try await storage.save(
                updated,
                to: "voice_messages",
                userId: userId,
                documentId: id
            )
        } catch {
            print("[VoiceMessageInboxService] Failed to mark listened: \(error)")
        }
    }

    private func startObserving() {
        listener?.remove()
        guard let storage = storageService, !userId.isEmpty else { return }

        listener = storage.observe(
            VoiceMessage.self,
            in: "voice_messages",
            userId: userId
        ) { [weak self] items in
            guard let self else { return }
            let sorted = self.sortMessages(items)
            let newUnread = self.detectNewUnreadMessages(
                previous: self.knownUnreadIds,
                current: sorted
            )
            self.messages = sorted
            self.knownUnreadIds = Set(sorted.compactMap { $0.isUnread ? $0.id : nil })

            if self.hasLoadedInitialSnapshot {
                for message in newUnread {
                    Task {
                        await self.notifyAboutVoiceMessage(message)
                    }
                }
            } else {
                self.hasLoadedInitialSnapshot = true
            }
        }
    }

    private func notifyAboutVoiceMessage(_ message: VoiceMessage) async {
        guard let notificationService else { return }
        let sender = message.caregiverName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = sender?.isEmpty == false ? "New voice message from \(sender!)" : "New caregiver voice message"
        let body = message.transcript?.isEmpty == false
            ? message.transcript!
            : "Open Noongil to listen."
        await notificationService.scheduleNotificationAfter(
            id: "voice_message_\(message.id ?? UUID().uuidString)",
            title: title,
            body: body,
            delay: 1,
            userInfo: [
                "type": "voice_message",
                "messageId": message.id ?? "",
            ]
        )
    }

    private func sortMessages(_ items: [VoiceMessage]) -> [VoiceMessage] {
        items.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    func detectNewUnreadMessages(
        previous: Set<String>,
        current: [VoiceMessage]
    ) -> [VoiceMessage] {
        current.filter { message in
            guard message.isUnread, let id = message.id else { return false }
            return !previous.contains(id)
        }
    }

    deinit {
        listener?.remove()
    }
}
