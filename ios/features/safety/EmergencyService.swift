import Foundation

/// Detects emergency voice triggers and manages the alert confirmation flow.
@MainActor
final class EmergencyService: ObservableObject {

    // MARK: - Constants

    static let confirmationTimeoutSeconds: TimeInterval = 15

    static let emergencyPhrases: [String] = [
        "i need help",
        "help me",
        "emergency",
        "call for help",
        "sos",
        "i fell",
        "call 911",
        "send help"
    ]

    // MARK: - State

    enum EmergencyState: String {
        case inactive
        case confirming      // Asked user "Should I contact [caregiver]?"
        case alerted         // Alert sent to caregiver
        case cancelled       // User said no
    }

    @Published private(set) var state: EmergencyState = .inactive

    private var timeoutTask: Task<Void, Never>?

    // MARK: - Detection

    /// Returns true if the text contains an emergency trigger phrase.
    func containsEmergencyTrigger(_ text: String) -> Bool {
        let lower = text.lowercased()
        return Self.emergencyPhrases.contains { lower.contains($0) }
    }

    // MARK: - Flow

    /// Initiates the emergency confirmation flow.
    func triggerEmergency() {
        guard state == .inactive else { return }
        state = .confirming
        HapticService.error()
        startTimeout()
        print("[EmergencyService] Emergency triggered — waiting for confirmation")
    }

    /// User confirmed the emergency. Send alert.
    func confirmEmergency() {
        guard state == .confirming else { return }
        timeoutTask?.cancel()
        state = .alerted
        sendAlert()
        print("[EmergencyService] Emergency confirmed — alert sent")
    }

    /// User cancelled the emergency ("no, I'm fine").
    func cancelEmergency() {
        guard state == .confirming else { return }
        timeoutTask?.cancel()
        state = .inactive
        print("[EmergencyService] Emergency cancelled by user")
    }

    /// Reset after alert is acknowledged.
    func reset() {
        timeoutTask?.cancel()
        state = .inactive
    }

    // MARK: - Messages

    /// Generates the confirmation prompt for the user.
    func confirmationMessage(caregiverName: String?) -> String {
        if let name = caregiverName {
            return "I'm going to contact \(name). Is that okay?"
        }
        return "I'm going to contact your emergency contact. Is that okay?"
    }

    // MARK: - Private

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.confirmationTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.state == .confirming {
                    self?.state = .alerted
                    self?.sendAlert()
                    print("[EmergencyService] No response — auto-alerting after \(Self.confirmationTimeoutSeconds)s")
                }
            }
        }
    }

    private func sendAlert() {
        // TODO: Wire to backend push notification + SMS when caregiver linking (F-01) is built.
        // For now, log locally and play alert sound.
        HapticService.error()
        print("[EmergencyService] ALERT SENT to emergency contacts")
    }
}
