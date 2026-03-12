import XCTest

@MainActor
final class VoiceMessageInboxServiceTests: XCTestCase {
    func testDetectNewUnreadMessagesOnlyReturnsUnreadUnknownMessages() {
        let service = VoiceMessageInboxService()
        let current = [
            VoiceMessage(
                caregiverId: "caregiver-1",
                caregiverName: "Amar",
                audioBase64: "AA==",
                mimeType: "audio/wav",
                durationSeconds: 4,
                transcript: nil,
                status: "unread",
                createdAt: "2026-03-12T15:00:00Z",
                listenedAt: nil
            ),
            VoiceMessage(
                caregiverId: "caregiver-1",
                caregiverName: "Amar",
                audioBase64: "AA==",
                mimeType: "audio/wav",
                durationSeconds: 4,
                transcript: nil,
                status: "listened",
                createdAt: "2026-03-12T14:00:00Z",
                listenedAt: "2026-03-12T14:05:00Z"
            ),
        ].enumerated().map { index, message in
            var mutable = message
            mutable.id = "msg-\(index + 1)"
            return mutable
        }

        let result = service.detectNewUnreadMessages(previous: ["msg-3"], current: current)
        XCTAssertEqual(result.map(\.id), ["msg-1"])
    }
}
