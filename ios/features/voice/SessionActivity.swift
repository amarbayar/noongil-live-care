import Foundation

enum SessionActivity {
    static func isActive(
        isCapturingAudio: Bool,
        isSpeakerActive: Bool,
        liveConnectionState: GeminiLiveService.ConnectionState
    ) -> Bool {
        if isCapturingAudio || isSpeakerActive {
            return true
        }

        switch liveConnectionState {
        case .connecting, .settingUp, .ready:
            return true
        case .disconnected, .error:
            return false
        }
    }
}
