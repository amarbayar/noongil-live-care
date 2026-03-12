import Foundation

/// Visual state of the companion orb. Mapped from VoicePipeline.PipelineState by the home screen.
enum OrbState: String {
    case resting
    case listening
    case processing
    case speaking
    case complete
    case checkInDue
    case error
}

/// Status for a single day in the glow history strip.
enum DayStatus {
    case good
    case mixed
    case concern
    case missed
}

/// One day's check-in status for the 7-day history row.
struct GlowDay: Identifiable {
    let id: Date
    let status: DayStatus
}

/// Progress through today's check-ins.
struct CheckInProgress {
    let completed: Int
    let total: Int
}
