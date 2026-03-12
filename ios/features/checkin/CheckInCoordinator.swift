import Foundation

/// Bridge between VoicePipeline and CheckInService.
/// When a check-in is active, speech is routed through the coordinator
/// instead of being sent directly to Gemini.
@MainActor
final class CheckInCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isCheckInActive: Bool = false
    @Published var checkInType: CheckInType?
    @Published var lastAssistantMessage: String?
    @Published var currentState: String = "idle"

    // MARK: - Dependencies

    var checkInService: CheckInService

    init(checkInService: CheckInService) {
        self.checkInService = checkInService
    }

    // MARK: - Public API

    /// Starts a check-in and returns the greeting for TTS.
    func beginCheckIn(type: CheckInType) async -> String? {
        guard !isCheckInActive else { return nil }

        do {
            isCheckInActive = true
            checkInType = type
            currentState = "greeting"
            let greeting = try await checkInService.startCheckIn(type: type)
            lastAssistantMessage = greeting
            currentState = checkInService.state.rawValue
            return greeting
        } catch {
            print("[CheckInCoordinator] Failed to start check-in: \(error)")
            isCheckInActive = false
            checkInType = nil
            currentState = "idle"
            return nil
        }
    }

    /// Processes user speech and returns the response for TTS.
    func handleUserSpeech(_ text: String) async -> String? {
        guard isCheckInActive else { return nil }

        do {
            let response = try await checkInService.processUserInput(text)
            lastAssistantMessage = response
            currentState = checkInService.state.rawValue

            // Check if check-in completed
            if checkInService.state == .completed {
                isCheckInActive = false
                checkInType = nil
                currentState = "idle"
            }

            return response.isEmpty ? nil : response
        } catch {
            print("[CheckInCoordinator] Error processing speech: \(error)")
            return nil
        }
    }

    /// Cancels the current check-in.
    func cancelCheckIn() async {
        await checkInService.cancelCheckIn()
        isCheckInActive = false
        checkInType = nil
        lastAssistantMessage = nil
        currentState = "idle"
    }
}
