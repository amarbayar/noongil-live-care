import XCTest

@MainActor
final class PhoneCameraServiceTests: XCTestCase {

    func testInitialState() {
        let service = PhoneCameraService()
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(service.currentPosition, .back)
        XCTAssertEqual(service.currentFilter, "none")
        XCTAssertNil(service.latestFilteredImage)
    }

    func testSetFilterUpdatesCurrentFilter() {
        let service = PhoneCameraService()
        service.setFilter("vintage")
        XCTAssertEqual(service.currentFilter, "vintage")
    }

    func testSetFilterWithUnknownFallsToNone() {
        let service = PhoneCameraService()
        service.setFilter("unknown_filter")
        XCTAssertEqual(service.currentFilter, "none")
    }

    func testSetFilterCyclesThroughAllFilters() {
        let service = PhoneCameraService()
        for filter in CameraFilterPipeline.availableFilters {
            service.setFilter(filter)
            XCTAssertEqual(service.currentFilter, filter)
        }
    }

    func testSetFilterAfterValidResetToNone() {
        let service = PhoneCameraService()
        service.setFilter("noir")
        XCTAssertEqual(service.currentFilter, "noir")
        service.setFilter("invalid")
        XCTAssertEqual(service.currentFilter, "none")
    }

    func testCapturePhotoReturnsNilWhenNotRunning() async {
        let service = PhoneCameraService()
        let result = await service.capturePhoto()
        XCTAssertNil(result)
    }

    func testCaptureCurrentFrameReturnsNilWhenNotRunning() {
        let service = PhoneCameraService()
        XCTAssertNil(service.captureCurrentFrame())
    }

    func testCaptureCurrentFrameAsJPEGReturnsNilWhenNotRunning() {
        let service = PhoneCameraService()
        XCTAssertNil(service.captureCurrentFrameAsJPEG())
    }

    func testCaptureCurrentFrameReturnsLatestFilteredImage() {
        let service = PhoneCameraService()
        let testImage = UIImage(systemName: "camera")!
        service.latestFilteredImage = testImage
        XCTAssertNotNil(service.captureCurrentFrame())
    }

    func testCaptureCurrentFrameAsJPEGReturnsDataWhenImagePresent() {
        let service = PhoneCameraService()
        service.latestFilteredImage = UIImage(systemName: "camera")!
        let data = service.captureCurrentFrameAsJPEG(quality: 0.5)
        XCTAssertNotNil(data)
        XCTAssertTrue((data?.count ?? 0) > 0)
    }

    // MARK: - Tool Declaration Structure

    func testToolDeclarationsContainExpectedTools() {
        let names = PhoneCameraService.toolDeclarations.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("take_photo"))
        XCTAssertTrue(names.contains("apply_filter"))
        XCTAssertEqual(names.count, 2)
    }

    func testTakePhotoToolHasCameraParameter() {
        let tool = PhoneCameraService.toolDeclarations.first { ($0["name"] as? String) == "take_photo" }
        XCTAssertNotNil(tool)

        let params = tool?["parameters"] as? [String: Any]
        let properties = params?["properties"] as? [String: Any]
        let camera = properties?["camera"] as? [String: Any]
        XCTAssertNotNil(camera)

        let enumValues = camera?["enum"] as? [String]
        XCTAssertEqual(enumValues, ["front", "back"])

        let required = params?["required"] as? [String]
        XCTAssertTrue(required?.contains("camera") == true)
    }

    func testTakePhotoToolHasFilterParameter() {
        let tool = PhoneCameraService.toolDeclarations.first { ($0["name"] as? String) == "take_photo" }
        let params = tool?["parameters"] as? [String: Any]
        let properties = params?["properties"] as? [String: Any]
        let filter = properties?["filter"] as? [String: Any]
        XCTAssertNotNil(filter)

        let enumValues = filter?["enum"] as? [String]
        XCTAssertEqual(enumValues, CameraFilterPipeline.availableFilters)
    }

    func testApplyFilterToolHasFilterParameter() {
        let tool = PhoneCameraService.toolDeclarations.first { ($0["name"] as? String) == "apply_filter" }
        XCTAssertNotNil(tool)

        let params = tool?["parameters"] as? [String: Any]
        let properties = params?["properties"] as? [String: Any]
        let filter = properties?["filter"] as? [String: Any]
        let enumValues = filter?["enum"] as? [String]
        XCTAssertEqual(enumValues, CameraFilterPipeline.availableFilters)

        let required = params?["required"] as? [String]
        XCTAssertTrue(required?.contains("filter") == true)
    }

    // MARK: - Stop Behavior

    func testStopWhenNotRunningIsNoop() {
        let service = PhoneCameraService()
        service.stop() // Should not crash
        XCTAssertFalse(service.isRunning)
    }
}
