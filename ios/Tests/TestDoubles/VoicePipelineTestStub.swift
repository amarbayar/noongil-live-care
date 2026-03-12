import Foundation

@MainActor
final class VoicePipeline {
    enum PipelineError: Error, Equatable {
        case voiceConsentRequired
        case notInitialized
    }

    var consentService: ConsentService?
    var pipelineMode: PipelineMode = .local

    func start() throws {
        if pipelineMode == .live || pipelineMode == .liveText {
            guard consentService?.voiceProcessingConsent == true else {
                throw PipelineError.voiceConsentRequired
            }
            throw PipelineError.notInitialized
        }

        throw PipelineError.notInitialized
    }
}
