import XCTest

final class LyriaRealtimeServiceTests: XCTestCase {

    // MARK: - Setup Message

    func testSetupMessageContainsModel() {
        let service = LyriaRealtimeService()
        let setup = service.buildSetupMessage()

        let setupBody = setup["setup"] as? [String: Any]
        XCTAssertNotNil(setupBody)
        XCTAssertEqual(setupBody?["model"] as? String, "models/\(Config.lyriaRealtimeModel)")
    }

    // MARK: - Weighted Prompt Message (clientContent format)

    func testWeightedPromptMessageFormat() {
        let service = LyriaRealtimeService()
        let message = service.buildWeightedPromptsMessage([
            LyriaRealtimeService.WeightedPrompt(text: "chill lofi", weight: 1.0),
            LyriaRealtimeService.WeightedPrompt(text: "piano", weight: 0.5),
        ])

        let clientContent = message["clientContent"] as? [String: Any]
        XCTAssertNotNil(clientContent, "Should use clientContent wrapper")

        let prompts = clientContent?["weightedPrompts"] as? [[String: Any]]
        XCTAssertEqual(prompts?.count, 2)
        XCTAssertEqual(prompts?[0]["text"] as? String, "chill lofi")
        XCTAssertEqual(prompts?[0]["weight"] as? Double, 1.0)
        XCTAssertEqual(prompts?[1]["text"] as? String, "piano")
        XCTAssertEqual(prompts?[1]["weight"] as? Double, 0.5)
    }

    // MARK: - Music Config Message (top-level musicGenerationConfig)

    func testMusicConfigMessageFormat() {
        let service = LyriaRealtimeService()
        let config = LyriaRealtimeService.MusicConfig(bpm: 120, brightness: 0.8, density: 0.5, guidance: 3.0)
        let message = service.buildMusicConfigMessage(config)

        let musicConfig = message["musicGenerationConfig"] as? [String: Any]
        XCTAssertNotNil(musicConfig, "Should be top-level musicGenerationConfig")
        XCTAssertEqual(musicConfig?["bpm"] as? Int, 120)
        XCTAssertEqual(musicConfig?["brightness"] as? Double, 0.8)
        XCTAssertEqual(musicConfig?["density"] as? Double, 0.5)
        XCTAssertEqual(musicConfig?["guidance"] as? Double, 3.0)
    }

    func testMusicConfigOmitsNilFields() {
        let service = LyriaRealtimeService()
        let config = LyriaRealtimeService.MusicConfig(bpm: 90)
        let message = service.buildMusicConfigMessage(config)

        let musicConfig = message["musicGenerationConfig"] as? [String: Any]
        XCTAssertNotNil(musicConfig)
        XCTAssertEqual(musicConfig?["bpm"] as? Int, 90)
        XCTAssertNil(musicConfig?["brightness"])
        XCTAssertNil(musicConfig?["density"])
        XCTAssertNil(musicConfig?["guidance"])
    }

    // MARK: - Playback Control Messages (playbackControl string)

    func testPlayMessageFormat() {
        let service = LyriaRealtimeService()
        let message = service.buildPlaybackMessage(.play)
        XCTAssertEqual(message["playbackControl"] as? String, "PLAY")
    }

    func testPauseMessageFormat() {
        let service = LyriaRealtimeService()
        let message = service.buildPlaybackMessage(.pause)
        XCTAssertEqual(message["playbackControl"] as? String, "PAUSE")
    }

    func testStopMessageFormat() {
        let service = LyriaRealtimeService()
        let message = service.buildPlaybackMessage(.stop)
        XCTAssertEqual(message["playbackControl"] as? String, "STOP")
    }

    func testResetContextMessageFormat() {
        let service = LyriaRealtimeService()
        let message = service.buildPlaybackMessage(.resetContext)
        XCTAssertEqual(message["playbackControl"] as? String, "RESET_CONTEXT")
    }

    // MARK: - State Machine

    func testInitialStateIsDisconnected() {
        let service = LyriaRealtimeService()
        XCTAssertEqual(service.state, .disconnected)
    }

    // MARK: - Audio Chunk Parsing

    func testParseAudioChunkFromServerContent() {
        let service = LyriaRealtimeService()
        let base64 = Data([0x01, 0x02, 0x03, 0x04]).base64EncodedString()
        let json: [String: Any] = [
            "serverContent": [
                "audioChunks": [
                    ["data": base64]
                ]
            ]
        ]

        var receivedData: Data?
        service.onAudioChunk = { data in
            receivedData = data
        }

        service.handleMessage(json)
        XCTAssertEqual(receivedData, Data([0x01, 0x02, 0x03, 0x04]))
    }

    func testParseSetupComplete() {
        let service = LyriaRealtimeService()
        let json: [String: Any] = ["setupComplete": [:] as [String: Any]]

        service.testSetState(.settingUp)
        service.handleMessage(json)
        XCTAssertEqual(service.state, .ready)
    }
}
