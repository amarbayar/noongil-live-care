import XCTest

final class CreativeResultTests: XCTestCase {

    func testResolvedMediaType_prefersPlayableVideoWhenDeclaredImage() {
        let result = CreativeResult(
            mediaType: .image,
            videoURL: URL(string: "file:///tmp/test.mp4"),
            prompt: "video"
        )

        XCTAssertEqual(result.resolvedMediaType, .video)
    }

    func testResolvedMediaType_prefersMusicWhenAudioExistsWithoutVideo() {
        let result = CreativeResult(
            mediaType: .image,
            audioData: Data([0x00, 0x01, 0x02]),
            prompt: "music"
        )

        XCTAssertEqual(result.resolvedMediaType, .music)
    }

    func testAnimationWithoutComposedVideoRequestsSeparateAudioTrack() {
        let result = CreativeResult(
            mediaType: .animation,
            videoURL: URL(string: "file:///tmp/test.mp4"),
            audioData: Data([0x00, 0x01, 0x02]),
            prompt: "animation"
        )

        XCTAssertTrue(result.shouldPlaySeparateAudioTrack)
    }

    func testMutatingMediaContentChangesEqualityRevision() {
        let original = CreativeResult(mediaType: .image, prompt: "same")
        var enriched = original
        enriched.videoURL = URL(string: "file:///tmp/result.mp4")

        XCTAssertNotEqual(original, enriched)
    }
}
