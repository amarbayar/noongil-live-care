import XCTest
import UIKit

final class CreativeArtifactLibraryServiceTests: XCTestCase {

    func testSaveArtifact_persistsAndReloadsLatestVideo() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        let sourceURL = rootURL.appendingPathComponent("source.mp4")
        try Data([0x00, 0x01, 0x02]).write(to: sourceURL)

        let savedResult = try service.saveArtifact(
            artifactId: "artifact-1",
            result: CreativeResult(
                mediaType: .video,
                videoURL: sourceURL,
                prompt: "waves at dusk"
            )
        )
        let restoredResult = try service.loadLatestArtifact(preferredMediaType: .video)

        XCTAssertNotNil(savedResult.videoURL)
        XCTAssertEqual(restoredResult?.prompt, "waves at dusk")
        XCTAssertEqual(restoredResult?.videoURL?.pathExtension, "mp4")
    }

    func testLoadLatestArtifact_prefersRequestedMediaType() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "artifact-image",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "quiet forest"
            )
        )

        try service.saveArtifact(
            artifactId: "artifact-music",
            result: CreativeResult(
                mediaType: .music,
                audioData: Data([0x03, 0x04, 0x05]),
                prompt: "gentle piano"
            )
        )

        let restoredMusic = try service.loadLatestArtifact(preferredMediaType: .music)

        XCTAssertEqual(restoredMusic?.resolvedMediaType, .music)
        XCTAssertEqual(restoredMusic?.prompt, "gentle piano")
    }
    func testSearchArtifacts_matchesBySubstring() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "art-1",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "sunset over mountains"
            )
        )
        try service.saveArtifact(
            artifactId: "art-2",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "sunrise at the beach"
            )
        )
        try service.saveArtifact(
            artifactId: "art-3",
            result: CreativeResult(
                mediaType: .music,
                audioData: Data([0x01]),
                prompt: "gentle piano"
            )
        )

        let results = try service.searchArtifacts(query: "sun", mediaType: nil)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.prompt.lowercased().contains("sun") })
    }

    func testSearchArtifacts_filtersByMediaType() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "art-img",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "sunset photo"
            )
        )
        try service.saveArtifact(
            artifactId: "art-mus",
            result: CreativeResult(
                mediaType: .music,
                audioData: Data([0x01]),
                prompt: "sunset melody"
            )
        )

        let results = try service.searchArtifacts(query: "sunset", mediaType: .image)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.mediaType, .image)
    }

    func testLoadArtifactById_returnsCorrectArtifact() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "find-me",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "golden hour"
            )
        )

        let loaded = try service.loadArtifact(by: "find-me")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.prompt, "golden hour")
    }

    func testLoadArtifactById_returnsNilForUnknownId() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        let loaded = try service.loadArtifact(by: "does-not-exist")
        XCTAssertNil(loaded)
    }

    func testDeleteArtifact_removesFromIndex() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "del-1",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "to be deleted"
            )
        )
        try service.saveArtifact(
            artifactId: "del-2",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "to keep"
            )
        )

        try service.deleteArtifact(id: "del-1")

        let loaded = try service.loadArtifact(by: "del-1")
        XCTAssertNil(loaded, "Deleted artifact should not be loadable")

        let kept = try service.loadArtifact(by: "del-2")
        XCTAssertNotNil(kept, "Other artifacts should remain")
    }

    func testDeleteArtifact_deletesFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "file-del",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "file delete test"
            )
        )

        let filesDir = rootURL.appendingPathComponent("files", isDirectory: true)
        let imageFile = filesDir.appendingPathComponent("file-del-image.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageFile.path), "Image file should exist before delete")

        try service.deleteArtifact(id: "file-del")

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageFile.path), "Image file should be deleted")
    }

    func testListArtifactIds_orderedByCreationDate() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let service = CreativeArtifactLibraryService(rootURL: rootURL)

        try service.saveArtifact(
            artifactId: "first",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "first"
            )
        )
        // Delay to ensure different createdAt timestamps
        Thread.sleep(forTimeInterval: 0.1)
        try service.saveArtifact(
            artifactId: "second",
            result: CreativeResult(
                mediaType: .image,
                image: makeLibraryTestImage(),
                prompt: "second"
            )
        )

        let ids = try service.listArtifactIds()
        XCTAssertEqual(ids, ["second", "first"], "Should be ordered newest first")
    }
}

private func makeLibraryTestImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    return renderer.image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}
