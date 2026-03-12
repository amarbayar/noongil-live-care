import AudioToolbox

/// Audio cues for orb state transitions.
enum AudioCueService {

    /// Ascending tone for check-in completion. Will swap to bundled .caf chime later.
    static func playCheckInComplete() {
        AudioServicesPlaySystemSound(1025)
    }

    /// Subtle acknowledgment sound when Mira processes user input.
    static func playAcknowledgment() {
        AudioServicesPlaySystemSound(1519) // Peek (subtle tap sound)
    }

    /// Confirmation sound when medication is taken.
    static func playMedicationTaken() {
        AudioServicesPlaySystemSound(1025) // Same chime as check-in for now
    }
}
