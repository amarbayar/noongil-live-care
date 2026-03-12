import XCTest

final class CompanionHomeCanvasLayoutTests: XCTestCase {

    func testNoCanvasUsesCenteredLargeOrb() {
        let layout = CompanionHomeCanvasLayout.make(canvas: nil)

        XCTAssertFalse(layout.showsCanvasOverlay)
        XCTAssertEqual(layout.orbMode, .centeredLarge)
        XCTAssertTrue(layout.showsHistory)
    }

    func testVisibleGeneratingCanvasUsesDockedOrbAndOverlay() {
        let canvas = CreativeCanvasState(
            artifactId: "artifact",
            mediaType: .image,
            prompt: "fox in a forest",
            status: .generating,
            statusMessage: "Drawing your image.",
            progressFraction: 0.42,
            progressDetail: "Adding more detail.",
            result: nil,
            isVisible: true
        )

        let layout = CompanionHomeCanvasLayout.make(canvas: canvas)

        XCTAssertTrue(layout.showsCanvasOverlay)
        XCTAssertEqual(layout.orbMode, .dockedCompact)
        XCTAssertFalse(layout.showsHistory)
    }

    func testHiddenReadyCanvasReturnsToCenteredOrb() {
        let canvas = CreativeCanvasState(
            artifactId: "artifact",
            mediaType: .video,
            prompt: "ocean at dusk",
            status: .ready,
            statusMessage: "Video ready.",
            progressFraction: 1.0,
            progressDetail: nil,
            result: CreativeResult(
                mediaType: .video,
                videoURL: URL(string: "file:///tmp/video.mp4"),
                prompt: "ocean at dusk"
            ),
            isVisible: false
        )

        let layout = CompanionHomeCanvasLayout.make(canvas: canvas)

        XCTAssertFalse(layout.showsCanvasOverlay)
        XCTAssertEqual(layout.orbMode, .centeredLarge)
        XCTAssertTrue(layout.showsHistory)
    }
}
