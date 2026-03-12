import XCTest

@MainActor
final class VoicePipelineSessionActivityTests: XCTestCase {

    func testHasActiveSessionIsFalseWhenIdleAndDisconnected() {
        XCTAssertFalse(
            SessionActivity.isActive(
                isCapturingAudio: false,
                isSpeakerActive: false,
                liveConnectionState: .disconnected
            )
        )
    }

    func testHasActiveSessionIsTrueWhileLiveSessionIsConnecting() {
        XCTAssertTrue(
            SessionActivity.isActive(
                isCapturingAudio: false,
                isSpeakerActive: false,
                liveConnectionState: .connecting
            )
        )
    }

    func testHasActiveSessionIsTrueWhenAudioCaptureIsRunning() {
        XCTAssertTrue(
            SessionActivity.isActive(
                isCapturingAudio: true,
                isSpeakerActive: false,
                liveConnectionState: .disconnected
            )
        )
    }
}
