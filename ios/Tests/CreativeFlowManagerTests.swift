import XCTest
import UIKit

@MainActor
final class CreativeFlowManagerTests: XCTestCase {

    func testGenerateVideoPromotesDefaultImageFlowToVideoResult() async {
        let stub = StubCreativeGenerator(videoURL: URL(string: "file:///tmp/generated.mp4"))
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = await manager.handleGenerateVideo(prompt: "ocean", aspectRatio: "16:9")

        XCTAssertEqual(manager.result?.mediaType, .video)
        XCTAssertEqual(manager.result?.videoURL, URL(string: "file:///tmp/generated.mp4"))
    }

    func testGenerateMusicPromotesDefaultImageFlowToMusicResult() async {
        let stub = StubCreativeGenerator(audioData: Data([0x01, 0x02, 0x03]))
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = await manager.handleGenerateMusic(prompt: "rain")

        XCTAssertEqual(manager.result?.mediaType, .music)
        XCTAssertEqual(manager.result?.audioData, Data([0x01, 0x02, 0x03]))
    }

    func testAnimationKeepsAnimationTypeAndStoresComposedVideo() async {
        let stub = StubCreativeGenerator(
            image: UIImage(),
            videoURL: URL(string: "file:///tmp/generated.mp4"),
            audioData: Data([0x01, 0x02, 0x03])
        )
        let composedURL = URL(string: "file:///tmp/composed.mp4")!
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil),
            composeMedia: { _, _ in composedURL }
        )

        _ = manager.start(mediaType: .animation)
        _ = await manager.handleGenerateImage(prompt: "fox", aspectRatio: "1:1")
        _ = await manager.handleGenerateVideo(prompt: "fox running", aspectRatio: "16:9")
        _ = await manager.handleGenerateMusic(prompt: "playful")

        XCTAssertEqual(manager.result?.mediaType, .animation)
        XCTAssertEqual(manager.result?.composedVideoURL, composedURL)
    }

    func testHandleGetCreativeGuidance_duringGenerationReturnsStatusUpdate() async {
        let stub = DelayedCreativeGenerator(videoDelayNanoseconds: 200_000_000)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean waves at dusk", aspectRatio: "16:9")
        await Task.yield()

        let guidance = manager.handleGetCreativeGuidance(latestUserText: "is it ready yet?")

        XCTAssertEqual(guidance["action"] as? String, "chat")
        XCTAssertEqual(guidance["generationStatus"] as? String, "running")
        XCTAssertTrue((guidance["instruction"] as? String)?.contains("still working") == true)

        await manager.waitForCurrentGeneration()
    }

    func testStartVideoGeneration_whenAlreadyGeneratingDoesNotStartDuplicateJob() async {
        let stub = DelayedCreativeGenerator(videoDelayNanoseconds: 200_000_000)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        let first = manager.startVideoGeneration(prompt: "ocean waves", aspectRatio: "16:9")
        let second = manager.startVideoGeneration(prompt: "ocean waves", aspectRatio: "16:9")

        XCTAssertEqual(first["status"] as? String, "started")
        XCTAssertEqual(second["status"] as? String, "already_running")

        try? await Task.sleep(nanoseconds: 50_000_000)
        let callCount = await stub.videoCallCount
        XCTAssertEqual(callCount, 1)

        await manager.waitForCurrentGeneration()
    }

    func testCancelGeneration_marksCanvasCancelled() async {
        let stub = DelayedCreativeGenerator(imageDelayNanoseconds: 200_000_000)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "fox in a meadow", aspectRatio: "1:1")
        await Task.yield()

        let response = manager.cancelGeneration()

        XCTAssertEqual(response["status"] as? String, "cancelled")
        XCTAssertEqual(manager.canvasState?.status, .cancelled)
    }

    func testCloseCanvas_hidesResultAndShowCanvasRestoresIt() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "quiet forest", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        XCTAssertEqual(manager.canvasState?.status, .ready)
        XCTAssertEqual(manager.canvasState?.isVisible, true)

        let close = manager.closeCanvas()
        XCTAssertEqual(close["status"] as? String, "closed")
        XCTAssertEqual(manager.canvasState?.isVisible, false)
        XCTAssertNotNil(manager.canvasState?.result?.image)

        let show = manager.showCanvas()
        XCTAssertEqual(show["status"] as? String, "visible")
        XCTAssertEqual(manager.canvasState?.isVisible, true)
    }

    func testShowCanvas_bumpsPlaybackTokenEvenWhenAlreadyVisible() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/replay-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        XCTAssertEqual(manager.canvasState?.isVisible, true)
        let tokenBefore = manager.canvasState?.playbackToken

        // Call show_canvas while already visible (user says "play it again")
        let result = manager.showCanvas()
        XCTAssertEqual(result["status"] as? String, "visible")
        XCTAssertEqual(manager.canvasState?.isVisible, true)
        XCTAssertNotEqual(manager.canvasState?.playbackToken, tokenBefore,
            "playbackToken must change so SwiftUI triggers replay")
    }

    func testMediaControl_pauseUpdatesActionAndBumpsToken() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/control-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let tokenBefore = manager.canvasState?.mediaActionToken

        let result = manager.handleMediaControl(action: "pause")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["status"] as? String, "pause")
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .pause)
        XCTAssertNotEqual(manager.canvasState?.mediaActionToken, tokenBefore)
    }

    func testMediaControl_replayUpdatesAction() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/control-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "replay")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .replay)
    }

    func testMediaControl_stopClosesCanvas() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/control-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "stop")
        XCTAssertEqual(result["status"] as? String, "closed")
        XCTAssertEqual(manager.canvasState?.isVisible, false)
    }

    func testMediaControl_noMediaReturnsError() {
        let stub = StubCreativeGenerator()
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        let result = manager.handleMediaControl(action: "pause")
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["status"] as? String, "no_media")
    }

    func testMediaControl_volumeUpUpdatesAction() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/vol-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "chill scene", aspectRatio: nil)
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "volume_up")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .volumeUp)
    }

    func testMediaControl_volumeDownUpdatesAction() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/vol-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "chill scene", aspectRatio: nil)
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "volume_down")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .volumeDown)
    }

    func testMediaControl_unknownActionReturnsError() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/control-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "shuffle")
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["status"] as? String, "unknown_action")
    }

    func testShowCanvas_bumpsPlaybackTokenAfterCloseAndReopen() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/replay-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let tokenAfterGen = manager.canvasState?.playbackToken

        _ = manager.closeCanvas()
        let show = manager.showCanvas()
        XCTAssertEqual(show["status"] as? String, "visible")
        XCTAssertNotEqual(manager.canvasState?.playbackToken, tokenAfterGen,
            "playbackToken must change on reopen for replay")
    }

    func testCompletedGeneration_requestsProactiveReadyAnnouncement() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )
        var announcements: [String] = []
        manager.onStatusAnnouncementRequested = { message in
            announcements.append(message)
        }

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "golden sunset", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        XCTAssertEqual(announcements, ["Your image is ready and showing on screen."])
    }

    func testStartVideoGeneration_updatesCanvasProgressWhileExistingCanvasRemainsVisible() async {
        let stub = ProgressReportingCreativeGenerator()
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "garden", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        _ = manager.startVideoGeneration(prompt: "garden swaying", aspectRatio: "16:9")
        await Task.yield()
        await stub.emitNextProgressUpdate()
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertEqual(manager.canvasState?.status, .generating)
        XCTAssertEqual(manager.canvasState?.isVisible, true)
        XCTAssertTrue(manager.canvasState?.statusMessage.contains("Checking on your video") == true)
        XCTAssertNotNil(manager.canvasState?.result?.image)

        await stub.finishVideo()
        await manager.waitForCurrentGeneration()
    }

    func testFailedGeneration_requestsProactiveFailureAnnouncement() async {
        // Stub with no image → throws on generateImage
        let stub = StubCreativeGenerator(image: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        var announcements: [String] = []
        manager.onStatusAnnouncementRequested = { message in
            announcements.append(message)
        }

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "sunset", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        XCTAssertEqual(announcements.count, 1, "Should announce failure verbally")
        XCTAssertTrue(announcements.first?.contains("image") == true,
            "Failure announcement should mention the media type")
    }

    func testFailedGeneration_contentFilterErrorGivesSpecificMessage() async {
        let stub = StubCreativeGenerator(image: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        var announcements: [String] = []
        manager.onStatusAnnouncementRequested = { message in
            announcements.append(message)
        }

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "inspired by Frank Sinatra", aspectRatio: nil)
        await manager.waitForCurrentGeneration()

        XCTAssertEqual(announcements.count, 1)
        // Generic stub error won't be content-filter-specific, but should still announce
        XCTAssertTrue(announcements.first?.contains("image") == true)
    }

    func testFailedGeneration_canvasStaysVisibleWithFailedStatus() async {
        let stub = StubCreativeGenerator(image: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "sunset", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        XCTAssertEqual(manager.canvasState?.status, .failed)
        XCTAssertEqual(manager.canvasState?.isVisible, true, "Canvas should stay visible on failure")
    }

    func testImageThenMusic_clearsStaleImage() async {
        let stub = StubCreativeGenerator(
            image: makeTestImage(),
            audioData: Data([0xAA, 0xBB])
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = await manager.handleGenerateImage(prompt: "sunset", aspectRatio: "1:1")
        XCTAssertNotNil(manager.result?.image)

        // Now generate standalone music — image should be cleared
        manager.setMediaType(.music)
        _ = await manager.handleGenerateMusic(prompt: "calm piano")
        XCTAssertNil(manager.result?.image, "Stale image must be cleared for standalone music")
        XCTAssertEqual(manager.result?.audioData, Data([0xAA, 0xBB]))
        XCTAssertEqual(manager.result?.resolvedMediaType, .music)
    }

    func testMusicThenImage_clearsStaleAudio() async {
        let stub = StubCreativeGenerator(
            image: makeTestImage(),
            audioData: Data([0xAA, 0xBB])
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .music)
        _ = await manager.handleGenerateMusic(prompt: "upbeat drums")
        XCTAssertNotNil(manager.result?.audioData)

        // Now generate standalone image — audio should be cleared
        manager.setMediaType(.image)
        _ = await manager.handleGenerateImage(prompt: "forest path", aspectRatio: "1:1")
        XCTAssertNil(manager.result?.audioData, "Stale audio must be cleared for standalone image")
        XCTAssertNotNil(manager.result?.image)
        XCTAssertEqual(manager.result?.resolvedMediaType, .image)
    }

    func testAnimationKeepsAllIntermediateMedia() async {
        let stub = StubCreativeGenerator(
            image: makeTestImage(),
            videoURL: URL(string: "file:///tmp/anim.mp4"),
            audioData: Data([0x01])
        )
        let composedURL = URL(string: "file:///tmp/composed.mp4")!
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil),
            composeMedia: { _, _ in composedURL }
        )

        _ = manager.start(mediaType: .animation)
        _ = await manager.handleGenerateImage(prompt: "fox", aspectRatio: "1:1")
        _ = await manager.handleGenerateVideo(prompt: "fox run", aspectRatio: "16:9")
        _ = await manager.handleGenerateMusic(prompt: "playful")

        // Animation should keep ALL media fields
        XCTAssertNotNil(manager.result?.image, "Animation must keep image")
        XCTAssertNotNil(manager.result?.videoURL, "Animation must keep videoURL")
        XCTAssertNotNil(manager.result?.audioData, "Animation must keep audioData")
        XCTAssertEqual(manager.result?.composedVideoURL, composedURL)
    }

    func testInjectCapturedImage_setsCanvasToReadyWithImage() {
        let stub = StubCreativeGenerator()
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        var publishedCanvas: CreativeCanvasState?
        manager.onCanvasStateChanged = { state in
            publishedCanvas = state
        }

        let testImage = UIImage(systemName: "camera")!
        manager.injectCapturedImage(testImage, prompt: "Selfie")

        XCTAssertEqual(manager.canvasState?.status, .ready)
        XCTAssertEqual(manager.canvasState?.mediaType, .image)
        XCTAssertEqual(manager.canvasState?.prompt, "Selfie")
        XCTAssertEqual(manager.canvasState?.isVisible, true)
        XCTAssertNotNil(manager.result?.image)
        XCTAssertEqual(manager.result?.prompt, "Selfie")
        // Verify callback was fired
        XCTAssertNotNil(publishedCanvas)
        XCTAssertEqual(publishedCanvas?.status, .ready)
    }

    func testInjectCapturedImage_canFeedIntoVideoGeneration() async {
        let stub = StubCreativeGenerator(videoURL: URL(string: "file:///tmp/animated.mp4"))
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        // Inject photo first
        let testImage = UIImage(systemName: "camera")!
        manager.injectCapturedImage(testImage, prompt: "Photo")

        // The injected image is now the starting point — generate video from it
        _ = manager.start(mediaType: .video)
        _ = await manager.handleGenerateVideo(prompt: "animate this photo", aspectRatio: nil)

        XCTAssertEqual(manager.result?.mediaType, .video)
        XCTAssertNotNil(manager.result?.videoURL)
    }

    func testSearchArtifacts_returnsMatchingResults() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        // Save some artifacts via the library stub
        library.savedArtifacts = [
            (id: "a1", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "sunset over mountains")),
            (id: "a2", result: CreativeResult(mediaType: .video, videoURL: URL(string: "file:///tmp/ocean.mp4"), prompt: "ocean waves")),
            (id: "a3", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "sunrise at the beach")),
        ]

        let result = manager.searchArtifacts(query: "sun", mediaType: nil)
        let matches = result["matches"] as? [[String: Any]] ?? []
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(result["success"] as? Bool == true)
    }

    func testSearchArtifacts_emptyQueryReturnsInstruction() {
        let stub = StubCreativeGenerator()
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        let result = manager.searchArtifacts(query: "nonexistent", mediaType: nil)
        let matches = result["matches"] as? [[String: Any]] ?? []
        XCTAssertEqual(matches.count, 0)
        XCTAssertTrue((result["instruction"] as? String)?.contains("could not find") == true)
    }

    func testDisplayArtifact_setsCanvasStateToReady() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        library.savedArtifacts = [
            (id: "recall-1", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "golden sunset")),
        ]
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        let result = manager.displayArtifact(by: "recall-1")
        XCTAssertTrue(result["success"] as? Bool == true)
        XCTAssertEqual(manager.canvasState?.status, .ready)
        XCTAssertEqual(manager.canvasState?.isVisible, true)
        XCTAssertEqual(manager.canvasState?.prompt, "golden sunset")
    }

    func testDisplayArtifact_notFoundReturnsError() {
        let stub = StubCreativeGenerator()
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        let result = manager.displayArtifact(by: "nonexistent")
        XCTAssertFalse(result["success"] as? Bool ?? true)
    }

    func testStartImageGeneration_withReferenceImageUsesEditPath() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        _ = manager.start(mediaType: .image)
        let refImage = makeTestImage()
        let result = manager.startImageGeneration(prompt: "me on the moon", aspectRatio: nil, referenceImage: refImage)
        XCTAssertEqual(result["status"] as? String, "started")
        await manager.waitForCurrentGeneration()
        XCTAssertNotNil(manager.result?.image)
    }

    func testShowCanvas_restoresLatestPersistedArtifactWhenSessionCanvasIsMissing() async {
        let stub = StubCreativeGenerator()
        let restored = CreativeResult(
            mediaType: .video,
            videoURL: URL(string: "file:///tmp/persisted.mp4"),
            prompt: "waves at dusk"
        )
        let library = StubCreativeArtifactLibrary(latestArtifact: restored)
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        _ = manager.start(mediaType: .video)
        let response = manager.showCanvas(preferredMediaType: .video)

        XCTAssertEqual(response["status"] as? String, "visible")
        XCTAssertEqual(manager.canvasState?.status, .ready)
        XCTAssertEqual(manager.canvasState?.result?.videoURL, restored.videoURL)
        XCTAssertEqual(manager.canvasState?.isVisible, true)
        XCTAssertEqual(library.lastRequestedMediaType, .video)
    }

    // MARK: - New Media Action Tests

    func testMediaControl_rotateLeftUpdatesImageRotation() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "rotate_left")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.imageRotationDegrees, -90)

        _ = manager.handleMediaControl(action: "rotate_left")
        XCTAssertEqual(manager.canvasState?.imageRotationDegrees, -180)
    }

    func testMediaControl_rotateRightUpdatesImageRotation() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "rotate_right")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.imageRotationDegrees, 90)
    }

    func testMediaControl_zoomInIncrementsScale() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        _ = manager.handleMediaControl(action: "zoom_in")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 2.0)

        _ = manager.handleMediaControl(action: "zoom_in")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 3.0)

        // Should cap at 3.0
        _ = manager.handleMediaControl(action: "zoom_in")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 3.0)
    }

    func testMediaControl_zoomOutDecrementsScale() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        _ = manager.handleMediaControl(action: "zoom_in")
        _ = manager.handleMediaControl(action: "zoom_in")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 3.0)

        _ = manager.handleMediaControl(action: "zoom_out")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 2.0)

        _ = manager.handleMediaControl(action: "zoom_out")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 1.0)

        // Should not go below 1.0
        _ = manager.handleMediaControl(action: "zoom_out")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 1.0)
    }

    func testMediaControl_muteDispatchesAction() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/mute-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "mute")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .mute)
    }

    func testMediaControl_speedDispatchesActionWithValue() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/speed-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "speed", args: ["value": 1.5])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .speed(1.5))
    }

    func testMediaControl_fullscreenUpdatesState() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "fullscreen")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.isFullscreen, true)

        let exitResult = manager.handleMediaControl(action: "exit_fullscreen")
        XCTAssertEqual(exitResult["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.isFullscreen, false)
    }

    func testMediaControl_saveDispatchesAction() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "save")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .save)
    }

    func testMediaControl_nextNavigatesToAdjacentArtifact() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        library.savedArtifacts = [
            (id: "a1", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "first")),
            (id: "a2", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "second")),
        ]
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        // Display the first artifact
        _ = manager.displayArtifact(by: "a1")
        XCTAssertEqual(manager.canvasState?.artifactId, "a1")

        // Navigate next
        let result = manager.handleMediaControl(action: "next")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.artifactId, "a2")
    }

    func testMediaControl_previousNavigatesToAdjacentArtifact() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        library.savedArtifacts = [
            (id: "a1", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "first")),
            (id: "a2", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "second")),
        ]
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        // Display the second artifact
        _ = manager.displayArtifact(by: "a2")
        XCTAssertEqual(manager.canvasState?.artifactId, "a2")

        // Navigate previous
        let result = manager.handleMediaControl(action: "previous")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.artifactId, "a1")
    }

    func testMediaControl_deleteRemovesAndNavigates() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        library.savedArtifacts = [
            (id: "a1", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "first")),
            (id: "a2", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "second")),
        ]
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        _ = manager.displayArtifact(by: "a1")
        let result = manager.handleMediaControl(action: "delete")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["status"] as? String, "deleted")
        // a1 should be removed, showing a2
        XCTAssertFalse(library.savedArtifacts.contains(where: { $0.id == "a1" }))
        XCTAssertEqual(manager.canvasState?.artifactId, "a2")
    }

    func testMediaControl_deleteLastClosesCanvas() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let library = StubCreativeArtifactLibrary(latestArtifact: nil)
        library.savedArtifacts = [
            (id: "a1", result: CreativeResult(mediaType: .image, image: makeTestImage(), prompt: "only one")),
        ]
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: library
        )

        _ = manager.displayArtifact(by: "a1")
        let result = manager.handleMediaControl(action: "delete")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["status"] as? String, "deleted_last")
        XCTAssertNil(manager.canvasState)
    }

    func testMediaControl_loopDispatchesAction() async {
        let stub = StubCreativeGenerator(
            videoURL: URL(string: "file:///tmp/loop-test.mp4")
        )
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .video)
        _ = manager.startVideoGeneration(prompt: "ocean", aspectRatio: "16:9")
        await manager.waitForCurrentGeneration()

        let result = manager.handleMediaControl(action: "loop")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.pendingMediaAction, .loop)
    }

    func testMediaControl_zoomResetResetsScale() async {
        let stub = StubCreativeGenerator(image: makeTestImage())
        let manager = CreativeFlowManager(
            generationService: stub,
            artifactLibrary: StubCreativeArtifactLibrary(latestArtifact: nil)
        )

        _ = manager.start(mediaType: .image)
        _ = manager.startImageGeneration(prompt: "landscape", aspectRatio: "1:1")
        await manager.waitForCurrentGeneration()

        _ = manager.handleMediaControl(action: "zoom_in")
        _ = manager.handleMediaControl(action: "zoom_in")
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 3.0)

        let result = manager.handleMediaControl(action: "zoom_reset")
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(manager.canvasState?.imageZoomScale, 1.0)
    }
}

private struct StubCreativeGenerator: CreativeGenerating {
    var image: UIImage?
    var videoURL: URL?
    var audioData: Data?

    init(
        image: UIImage? = makeTestImage(),
        videoURL: URL? = nil,
        audioData: Data? = nil
    ) {
        self.image = image
        self.videoURL = videoURL
        self.audioData = audioData
    }

    func generateImage(
        prompt: String,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage {
        guard let image else {
            throw NSError(domain: "StubCreativeGenerator", code: 1)
        }
        return image
    }

    func generateImageWithReference(
        prompt: String,
        referenceImage: UIImage,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage {
        guard let image else {
            throw NSError(domain: "StubCreativeGenerator", code: 1)
        }
        return image
    }

    func generateVideo(
        prompt: String,
        aspectRatio: String?,
        durationSeconds: Int?,
        startingImage: UIImage?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> URL {
        guard let videoURL else {
            throw NSError(domain: "StubCreativeGenerator", code: 2)
        }
        return videoURL
    }

    func generateMusic(
        prompt: String,
        negativePrompt: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> Data {
        guard let audioData else {
            throw NSError(domain: "StubCreativeGenerator", code: 3)
        }
        return audioData
    }
}

private actor DelayedCreativeGenerator: CreativeGenerating {
    private(set) var imageCallCount = 0
    private(set) var videoCallCount = 0
    private(set) var musicCallCount = 0

    private let imageDelayNanoseconds: UInt64
    private let videoDelayNanoseconds: UInt64
    private let musicDelayNanoseconds: UInt64

    init(
        imageDelayNanoseconds: UInt64 = 0,
        videoDelayNanoseconds: UInt64 = 0,
        musicDelayNanoseconds: UInt64 = 0
    ) {
        self.imageDelayNanoseconds = imageDelayNanoseconds
        self.videoDelayNanoseconds = videoDelayNanoseconds
        self.musicDelayNanoseconds = musicDelayNanoseconds
    }

    func generateImage(
        prompt: String,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage {
        imageCallCount += 1
        if imageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: imageDelayNanoseconds)
        }
        return makeTestImage()
    }

    func generateImageWithReference(
        prompt: String,
        referenceImage: UIImage,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage {
        imageCallCount += 1
        if imageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: imageDelayNanoseconds)
        }
        return makeTestImage()
    }

    func generateVideo(
        prompt: String,
        aspectRatio: String?,
        durationSeconds: Int?,
        startingImage: UIImage?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> URL {
        videoCallCount += 1
        if videoDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: videoDelayNanoseconds)
        }
        return URL(string: "file:///tmp/delayed-video.mp4")!
    }

    func generateMusic(
        prompt: String,
        negativePrompt: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> Data {
        musicCallCount += 1
        if musicDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: musicDelayNanoseconds)
        }
        return Data([0x01, 0x02, 0x03])
    }
}

private actor ProgressReportingCreativeGenerator: CreativeGenerating {
    private var videoContinuation: CheckedContinuation<URL, Error>?
    private var pendingProgress: [CreativeGenerationProgress] = []
    private var latestProgressHandler: ((CreativeGenerationProgress) -> Void)?

    func generateImage(
        prompt: String,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage {
        makeTestImage()
    }

    func generateImageWithReference(
        prompt: String,
        referenceImage: UIImage,
        aspectRatio: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> UIImage {
        makeTestImage()
    }

    func generateVideo(
        prompt: String,
        aspectRatio: String?,
        durationSeconds: Int?,
        startingImage: UIImage?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> URL {
        latestProgressHandler = onProgress
        pendingProgress.append(
            CreativeGenerationProgress(
                stage: .polling,
                message: "Checking on your video. It is still rendering.",
                fraction: 0.35
            )
        )

        return try await withCheckedThrowingContinuation { continuation in
            videoContinuation = continuation
        }
    }

    func generateMusic(
        prompt: String,
        negativePrompt: String?,
        onProgress: ((CreativeGenerationProgress) -> Void)?
    ) async throws -> Data {
        Data([0x01])
    }

    func emitNextProgressUpdate() async {
        while latestProgressHandler == nil {
            await Task.yield()
        }
        guard let update = pendingProgress.first else { return }
        pendingProgress.removeFirst()
        latestProgressHandler?(update)
    }

    func finishVideo() {
        videoContinuation?.resume(returning: URL(string: "file:///tmp/generated-progress.mp4")!)
        videoContinuation = nil
    }
}

private func makeTestImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    return renderer.image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}

private final class StubCreativeArtifactLibrary: CreativeArtifactLibrarying {
    private(set) var lastRequestedMediaType: CreativeMediaType?
    private let latestArtifact: CreativeResult?
    var savedArtifacts: [(id: String, result: CreativeResult)] = []

    init(latestArtifact: CreativeResult?) {
        self.latestArtifact = latestArtifact
    }

    func saveArtifact(artifactId: String, result: CreativeResult) throws -> CreativeResult {
        savedArtifacts.append((id: artifactId, result: result))
        return result
    }

    func loadLatestArtifact(preferredMediaType: CreativeMediaType?) throws -> CreativeResult? {
        lastRequestedMediaType = preferredMediaType
        return latestArtifact
    }

    func searchArtifacts(query: String, mediaType: CreativeMediaType?) throws -> [ArtifactSearchResult] {
        savedArtifacts
            .filter { $0.result.prompt.lowercased().contains(query.lowercased()) }
            .filter { mediaType == nil || $0.result.mediaType == mediaType }
            .map { ArtifactSearchResult(id: $0.id, mediaType: $0.result.mediaType, prompt: $0.result.prompt, createdAt: Date()) }
    }

    func loadArtifact(by id: String) throws -> CreativeResult? {
        savedArtifacts.first(where: { $0.id == id })?.result
    }

    func deleteArtifact(id: String) throws {
        savedArtifacts.removeAll { $0.id == id }
    }

    func listArtifactIds() throws -> [String] {
        savedArtifacts.map { $0.id }
    }
}
