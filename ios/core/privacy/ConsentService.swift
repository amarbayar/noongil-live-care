import Foundation

/// Tracks user consent state for health data, AI analysis, voice processing, and legal terms.
/// Stores in UserDefaults with Firestore backup on grant.
@MainActor
final class ConsentService: ObservableObject {

    // MARK: - Consent Flags

    @Published var healthDataConsent: Bool {
        didSet { save("consent_healthData", healthDataConsent) }
    }
    @Published var aiAnalysisConsent: Bool {
        didSet { save("consent_aiAnalysis", aiAnalysisConsent) }
    }
    @Published var voiceProcessingConsent: Bool {
        didSet { save("consent_voiceProcessing", voiceProcessingConsent) }
    }
    @Published var termsAccepted: Bool {
        didSet { save("consent_terms", termsAccepted) }
    }
    @Published var privacyPolicyAccepted: Bool {
        didSet { save("consent_privacy", privacyPolicyAccepted) }
    }
    @Published var ageConfirmed: Bool {
        didSet { save("consent_age", ageConfirmed) }
    }

    // MARK: - Computed

    var allConsentsGranted: Bool {
        healthDataConsent
        && aiAnalysisConsent
        && voiceProcessingConsent
        && termsAccepted
        && privacyPolicyAccepted
        && ageConfirmed
    }

    // MARK: - Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.healthDataConsent = defaults.bool(forKey: "consent_healthData")
        self.aiAnalysisConsent = defaults.bool(forKey: "consent_aiAnalysis")
        self.voiceProcessingConsent = defaults.bool(forKey: "consent_voiceProcessing")
        self.termsAccepted = defaults.bool(forKey: "consent_terms")
        self.privacyPolicyAccepted = defaults.bool(forKey: "consent_privacy")
        self.ageConfirmed = defaults.bool(forKey: "consent_age")
    }

    // MARK: - Bulk Grant/Revoke

    func grantAll() {
        healthDataConsent = true
        aiAnalysisConsent = true
        voiceProcessingConsent = true
        termsAccepted = true
        privacyPolicyAccepted = true
        ageConfirmed = true
    }

    func revokeAll() {
        healthDataConsent = false
        aiAnalysisConsent = false
        voiceProcessingConsent = false
        termsAccepted = false
        privacyPolicyAccepted = false
        ageConfirmed = false
    }

    // MARK: - Private

    private func save(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
    }
}
