import Foundation

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case condition
    case speechAssessment
    case checkInSchedule
    case complete
}

// MARK: - User Condition

enum UserCondition: String, CaseIterable, Codable {
    case parkinsons = "parkinsons"
    case als = "als"
    case ms = "ms"
    case arthritis = "arthritis"
    case other = "other"

    var displayName: String {
        switch self {
        case .parkinsons: return "Parkinson's"
        case .als: return "ALS"
        case .ms: return "MS"
        case .arthritis: return "Arthritis"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .parkinsons: return "hand.raised"
        case .als: return "figure.arms.open"
        case .ms: return "brain.head.profile"
        case .arthritis: return "hand.point.up"
        case .other: return "heart"
        }
    }
}

// MARK: - Onboarding Service

/// Manages the step-by-step onboarding flow and captured data.
@MainActor
final class OnboardingService: ObservableObject {

    @Published var currentStep: OnboardingStep = .welcome
    @Published var userName: String = ""
    @Published var selectedCondition: UserCondition?
    @Published var speechAccommodation: SpeechAccommodationLevel = .none
    @Published var morningTime: String = "08:00"
    @Published var eveningTime: String = "20:00"
    @Published var morningEnabled: Bool = true
    @Published var eveningEnabled: Bool = true

    private let steps = OnboardingStep.allCases

    /// Progress from 0.0 (welcome) to 1.0 (complete).
    var progress: Float {
        guard let index = steps.firstIndex(of: currentStep) else { return 0 }
        let maxIndex = steps.count - 1
        return maxIndex > 0 ? Float(index) / Float(maxIndex) : 0
    }

    func advance() {
        guard let index = steps.firstIndex(of: currentStep),
              index + 1 < steps.count else { return }
        currentStep = steps[index + 1]
    }

    func goBack() {
        guard let index = steps.firstIndex(of: currentStep),
              index > 0 else { return }
        currentStep = steps[index - 1]
    }

    /// Builds a CheckInSchedule from the captured data.
    func buildSchedule() -> CheckInSchedule {
        CheckInSchedule(
            morningTime: morningTime,
            eveningTime: eveningTime,
            morningEnabled: morningEnabled,
            eveningEnabled: eveningEnabled
        )
    }
}
