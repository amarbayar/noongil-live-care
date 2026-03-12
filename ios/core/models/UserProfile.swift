import Foundation
import FirebaseFirestore

// MARK: - Speech Accommodation

/// Level of speech accommodation for dysarthric users.
/// Adjusts VAD silence timeout, threshold, and ASR confidence expectations.
enum SpeechAccommodationLevel: String, Codable, CaseIterable {
    case none = "none"
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"
}

/// Concrete VAD/ASR parameters for a given accommodation level.
struct SpeechAccommodationConfig {
    let minSilenceDuration: Float
    let vadThreshold: Float
    let minSpeechDuration: Float
    let maxSpeechDuration: Float
    let confidenceThreshold: Float

    static func config(for level: SpeechAccommodationLevel) -> SpeechAccommodationConfig {
        switch level {
        case .none:
            return SpeechAccommodationConfig(
                minSilenceDuration: 0.25,
                vadThreshold: 0.5,
                minSpeechDuration: 0.5,
                maxSpeechDuration: 30.0,
                confidenceThreshold: 0.6
            )
        case .mild:
            return SpeechAccommodationConfig(
                minSilenceDuration: 1.5,
                vadThreshold: 0.45,
                minSpeechDuration: 0.5,
                maxSpeechDuration: 30.0,
                confidenceThreshold: 0.4
            )
        case .moderate:
            return SpeechAccommodationConfig(
                minSilenceDuration: 2.5,
                vadThreshold: 0.35,
                minSpeechDuration: 0.5,
                maxSpeechDuration: 45.0,
                confidenceThreshold: 0.3
            )
        case .severe:
            return SpeechAccommodationConfig(
                minSilenceDuration: 4.0,
                vadThreshold: 0.25,
                minSpeechDuration: 0.3,
                maxSpeechDuration: 60.0,
                confidenceThreshold: 0.2
            )
        }
    }
}

// MARK: - Check-In Schedule

struct CheckInSchedule: Codable {
    var morningTime: String?       // "08:00"
    var eveningTime: String?       // "20:00"
    var morningEnabled: Bool
    var eveningEnabled: Bool

    init(
        morningTime: String? = "08:00",
        eveningTime: String? = "20:00",
        morningEnabled: Bool = true,
        eveningEnabled: Bool = true
    ) {
        self.morningTime = morningTime
        self.eveningTime = eveningTime
        self.morningEnabled = morningEnabled
        self.eveningEnabled = eveningEnabled
    }
}

// MARK: - User Profile

/// Stored at /users/{userId}/profile/main in Firestore.
struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String?
    var companionName: String
    var language: String
    var timezone: String
    var checkInSchedule: CheckInSchedule?
    var speechAccommodationLevel: SpeechAccommodationLevel
    var baselineASRConfidence: Float?
    var onboardingCompleted: Bool
    var weekNumber: Int            // weeks since first check-in (progressive reveal)
    let createdAt: Date
    var updatedAt: Date

    init(
        companionName: String = "Mira",
        language: String = "en",
        timezone: String = TimeZone.current.identifier
    ) {
        self.companionName = companionName
        self.language = language
        self.timezone = timezone
        self.speechAccommodationLevel = .none
        self.onboardingCompleted = false
        self.weekNumber = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
