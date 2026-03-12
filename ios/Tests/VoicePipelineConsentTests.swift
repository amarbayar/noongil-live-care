import XCTest

@MainActor
final class VoicePipelineConsentTests: XCTestCase {

    private var pipeline: VoicePipeline!
    private var consentService: ConsentService!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "VoicePipelineConsentTests")!
        defaults.removePersistentDomain(forName: "VoicePipelineConsentTests")
        consentService = ConsentService(defaults: defaults)
        pipeline = VoicePipeline()
        pipeline.consentService = consentService
    }

    // MARK: - Live mode requires voice consent

    func testLiveModeThrowsWithoutVoiceConsent() {
        pipeline.pipelineMode = .live
        consentService.voiceProcessingConsent = false

        XCTAssertThrowsError(try pipeline.start()) { error in
            XCTAssertEqual(
                (error as? VoicePipeline.PipelineError),
                VoicePipeline.PipelineError.voiceConsentRequired
            )
        }
    }

    func testLiveTextModeThrowsWithoutVoiceConsent() {
        pipeline.pipelineMode = .liveText
        consentService.voiceProcessingConsent = false

        XCTAssertThrowsError(try pipeline.start()) { error in
            XCTAssertEqual(
                (error as? VoicePipeline.PipelineError),
                VoicePipeline.PipelineError.voiceConsentRequired
            )
        }
    }

    func testLocalModeDoesNotRequireVoiceConsent() {
        pipeline.pipelineMode = .local
        consentService.voiceProcessingConsent = false

        // Local mode won't start without model initialization, but it should NOT
        // throw voiceConsentRequired — it should throw notInitialized instead.
        XCTAssertThrowsError(try pipeline.start()) { error in
            XCTAssertNotEqual(
                (error as? VoicePipeline.PipelineError),
                VoicePipeline.PipelineError.voiceConsentRequired
            )
        }
    }

    func testLiveModeStartsWithVoiceConsent() {
        pipeline.pipelineMode = .live
        consentService.voiceProcessingConsent = true

        // This will fail at audio session config (no hardware in test), but
        // it should NOT throw voiceConsentRequired.
        do {
            try pipeline.start()
            // If it somehow starts, that's fine too
        } catch let error as VoicePipeline.PipelineError {
            XCTAssertNotEqual(error, .voiceConsentRequired,
                              "Should not throw voiceConsentRequired when consent is granted")
        } catch {
            // Other errors (audio session, etc.) are expected in test environment
        }
    }

    func testNilConsentServiceBlocksLiveMode() {
        pipeline.consentService = nil
        pipeline.pipelineMode = .live

        XCTAssertThrowsError(try pipeline.start()) { error in
            XCTAssertEqual(
                (error as? VoicePipeline.PipelineError),
                VoicePipeline.PipelineError.voiceConsentRequired
            )
        }
    }
}
