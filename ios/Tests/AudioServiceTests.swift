import XCTest
import AVFoundation

final class AudioServiceTests: XCTestCase {

    func testMakeSessionStrategy_localUsesVoiceChatWithoutEngineVoiceProcessing() {
        let strategy = AudioService.makeSessionStrategy(for: .local, hasBluetoothInput: false)

        XCTAssertEqual(strategy.sessionMode, .voiceChat)
        XCTAssertEqual(strategy.categoryOptions, [.allowBluetooth, .defaultToSpeaker])
        XCTAssertFalse(strategy.engineVoiceProcessingEnabled)
    }

    func testMakeSessionStrategy_liveWithBluetoothKeepsDefaultModeNoVoiceProcessing() {
        let strategy = AudioService.makeSessionStrategy(for: .live, hasBluetoothInput: true)

        // Bluetooth HFP provides its own echo cancellation
        XCTAssertEqual(strategy.sessionMode, .default)
        XCTAssertEqual(strategy.categoryOptions, [.allowBluetooth, .defaultToSpeaker])
        XCTAssertFalse(strategy.engineVoiceProcessingEnabled)
    }

    func testMakeSessionStrategy_liveWithoutBluetoothEnablesVoiceProcessing() {
        let strategy = AudioService.makeSessionStrategy(for: .live, hasBluetoothInput: false)

        // Built-in mic + speaker needs VoiceProcessingIO for AEC
        XCTAssertEqual(strategy.sessionMode, .voiceChat)
        XCTAssertEqual(strategy.categoryOptions, [.allowBluetooth, .defaultToSpeaker])
        XCTAssertTrue(strategy.engineVoiceProcessingEnabled)
    }

    func testMakeSessionStrategy_liveTextWithoutBluetoothEnablesVoiceProcessing() {
        let strategy = AudioService.makeSessionStrategy(for: .liveText, hasBluetoothInput: false)

        XCTAssertEqual(strategy.sessionMode, .voiceChat)
        XCTAssertTrue(strategy.engineVoiceProcessingEnabled)
    }

    func testMakeSessionStrategy_liveTextWithBluetoothNoVoiceProcessing() {
        let strategy = AudioService.makeSessionStrategy(for: .liveText, hasBluetoothInput: true)

        XCTAssertEqual(strategy.sessionMode, .default)
        XCTAssertFalse(strategy.engineVoiceProcessingEnabled)
    }
}
