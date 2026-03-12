import Foundation

struct CompanionHomeOrbPresentation: Equatable {
    let title: String
    let subtitle: String
    let accessibilityLabel: String
    let accessibilityHint: String

    static func make(
        state: OrbState,
        isSessionActive: Bool,
        canStartSession: Bool,
        isConnecting: Bool = false
    ) -> CompanionHomeOrbPresentation {
        switch state {
        case .resting:
            if isSessionActive {
                return CompanionHomeOrbPresentation(
                    title: "Calm",
                    subtitle: "Tap the orb to end, or speak again when you’re ready.",
                    accessibilityLabel: "Mira is calm",
                    accessibilityHint: "Tap the orb to end this voice session"
                )
            }
            if canStartSession {
                return CompanionHomeOrbPresentation(
                    title: "Calm",
                    subtitle: "Tap the orb when you want to talk.",
                    accessibilityLabel: "Mira is calm and ready",
                    accessibilityHint: "Tap the orb to start a voice session"
                )
            }
            return CompanionHomeOrbPresentation(
                title: "Preparing voice",
                subtitle: "Voice is still getting ready.",
                accessibilityLabel: "Voice is preparing",
                accessibilityHint: "Wait for voice setup to finish before starting"
            )
        case .listening:
            return CompanionHomeOrbPresentation(
                title: "Listening",
                subtitle: "I’m with you. Speak naturally, then tap the orb when you’re done.",
                accessibilityLabel: "Mira is listening",
                accessibilityHint: "Tap the orb to end this voice session"
            )
        case .processing:
            if isConnecting {
                return CompanionHomeOrbPresentation(
                    title: "Connecting",
                    subtitle: "Hold on. Mira is getting ready to listen.",
                    accessibilityLabel: "Mira is connecting",
                    accessibilityHint: "Wait until Mira is listening before you start speaking"
                )
            }
            return CompanionHomeOrbPresentation(
                title: "Thinking",
                subtitle: "Mira is working through a response.",
                accessibilityLabel: "Mira is thinking",
                accessibilityHint: "Wait for Mira to respond, or tap the orb to stop"
            )
        case .speaking:
            return CompanionHomeOrbPresentation(
                title: "Speaking",
                subtitle: "Mira is talking back. Tap the orb to end.",
                accessibilityLabel: "Mira is speaking",
                accessibilityHint: "Tap the orb to end this voice session"
            )
        case .complete:
            return CompanionHomeOrbPresentation(
                title: "Complete",
                subtitle: "That session is finished.",
                accessibilityLabel: "Session complete",
                accessibilityHint: "Tap the orb to start a new voice session"
            )
        case .checkInDue:
            return CompanionHomeOrbPresentation(
                title: "Check-in due",
                subtitle: "Tap the orb to begin today’s session.",
                accessibilityLabel: "Check-in is due",
                accessibilityHint: "Tap the orb to start today’s voice session"
            )
        case .error:
            return CompanionHomeOrbPresentation(
                title: "Connection issue",
                subtitle: "Tap the orb to try again.",
                accessibilityLabel: "Mira is having trouble connecting",
                accessibilityHint: "Tap the orb to retry the voice session"
            )
        }
    }
}
