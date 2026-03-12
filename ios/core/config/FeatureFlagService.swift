import Foundation

/// Typed feature flags loaded from bundled JSON. Designed for future Firebase Remote Config swap-in.
@MainActor
final class FeatureFlagService: ObservableObject {

    // MARK: - Published Flags

    @Published var checkInEnabled: Bool = true
    @Published var glassesCameraEnabled: Bool = true
    @Published var caregiverLinkingEnabled: Bool = false
    @Published var doctorReportEnabled: Bool = false
    @Published var voiceBiomarkerEnabled: Bool = false
    @Published var enhancementModeDefault: String = "SBR"
    @Published var pipelineModeDefault: String = "local"
    @Published var maxCheckInQuestions: Int = 5
    @Published var correlationEngineEnabled: Bool = false
    @Published var medicationRemindersEnabled: Bool = false
    @Published var companionName: String = "Mira"
    @Published var creativeGenerationEnabled: Bool = false
    @Published var unifiedGuidanceEnabled: Bool = false

    // MARK: - Init

    init() {
        loadBundledFlags()
    }

    // MARK: - Load from Bundle

    func loadBundledFlags() {
        guard let url = Bundle.main.url(
            forResource: "feature-flags",
            withExtension: "json",
            subdirectory: "config"
        ) else {
            print("[FeatureFlagService] feature-flags.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[FeatureFlagService] Failed to parse feature-flags.json")
                return
            }
            applyFlags(dict)
        } catch {
            print("[FeatureFlagService] Error loading feature-flags.json: \(error)")
        }
    }

    // MARK: - Apply (future Firebase Remote Config hook)

    func applyFlags(_ dict: [String: Any]) {
        if let v = dict["check_in_enabled"] as? Bool { checkInEnabled = v }
        if let v = dict["glasses_camera_enabled"] as? Bool { glassesCameraEnabled = v }
        if let v = dict["caregiver_linking_enabled"] as? Bool { caregiverLinkingEnabled = v }
        if let v = dict["doctor_report_enabled"] as? Bool { doctorReportEnabled = v }
        if let v = dict["voice_biomarker_enabled"] as? Bool { voiceBiomarkerEnabled = v }
        if let v = dict["enhancement_mode_default"] as? String { enhancementModeDefault = v }
        if let v = dict["pipeline_mode_default"] as? String { pipelineModeDefault = v }
        if let v = dict["max_check_in_questions"] as? Int { maxCheckInQuestions = v }
        if let v = dict["correlation_engine_enabled"] as? Bool { correlationEngineEnabled = v }
        if let v = dict["medication_reminders_enabled"] as? Bool { medicationRemindersEnabled = v }
        if let v = dict["companion_name"] as? String { companionName = v }
        if let v = dict["creative_generation_enabled"] as? Bool { creativeGenerationEnabled = v }
        if let v = dict["unified_guidance_enabled"] as? Bool { unifiedGuidanceEnabled = v }
    }
}
