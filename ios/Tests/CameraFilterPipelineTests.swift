import XCTest
import CoreImage

final class CameraFilterPipelineTests: XCTestCase {

    private let context = CIContext()

    private func makeTestImage() -> CIImage {
        // 100x100 red image
        CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testAvailableFiltersContainsExpected() {
        let filters = CameraFilterPipeline.availableFilters
        XCTAssertTrue(filters.contains("none"))
        XCTAssertTrue(filters.contains("warm"))
        XCTAssertTrue(filters.contains("cool"))
        XCTAssertTrue(filters.contains("vintage"))
        XCTAssertTrue(filters.contains("noir"))
        XCTAssertTrue(filters.contains("vivid"))
        XCTAssertEqual(filters.count, 6)
    }

    func testAllFiltersProduceOutput() {
        let input = makeTestImage()
        for name in CameraFilterPipeline.availableFilters {
            let output = CameraFilterPipeline.apply(filterName: name, to: input)
            XCTAssertEqual(output.extent.width, 100, "Filter '\(name)' changed width")
            XCTAssertEqual(output.extent.height, 100, "Filter '\(name)' changed height")
        }
    }

    func testNoneReturnsIdenticalImage() {
        let input = makeTestImage()
        let output = CameraFilterPipeline.apply(filterName: "none", to: input)
        XCTAssertEqual(input.extent, output.extent)
    }

    func testUnknownFilterFallsBackToPassthrough() {
        let input = makeTestImage()
        let output = CameraFilterPipeline.apply(filterName: "doesNotExist", to: input)
        XCTAssertEqual(input.extent, output.extent)
    }

    func testEmptyStringFilterFallsBackToPassthrough() {
        let input = makeTestImage()
        let output = CameraFilterPipeline.apply(filterName: "", to: input)
        XCTAssertEqual(input.extent, output.extent)
    }

    func testNoirProducesDifferentPixelsThanInput() {
        let input = makeTestImage()
        let output = CameraFilterPipeline.apply(filterName: "noir", to: input)

        // Render both to bitmaps and compare — noir should alter the red channel
        guard let inputCG = context.createCGImage(input, from: input.extent),
              let outputCG = context.createCGImage(output, from: output.extent) else {
            XCTFail("Failed to render CIImage to CGImage")
            return
        }

        // Compare raw data — noir should produce different pixels from pure red input
        let inputData = UIImage(cgImage: inputCG).pngData()
        let outputData = UIImage(cgImage: outputCG).pngData()
        XCTAssertNotEqual(inputData, outputData, "Noir filter should produce different pixel data")
    }

    func testVintageProducesDifferentPixelsThanInput() {
        let input = makeTestImage()
        let output = CameraFilterPipeline.apply(filterName: "vintage", to: input)

        guard let inputCG = context.createCGImage(input, from: input.extent),
              let outputCG = context.createCGImage(output, from: output.extent) else {
            XCTFail("Failed to render CIImage to CGImage")
            return
        }

        let inputData = UIImage(cgImage: inputCG).pngData()
        let outputData = UIImage(cgImage: outputCG).pngData()
        XCTAssertNotEqual(inputData, outputData, "Vintage filter should produce different pixel data")
    }

    func testAllFiltersRenderToCGImage() {
        let input = makeTestImage()
        for name in CameraFilterPipeline.availableFilters {
            let output = CameraFilterPipeline.apply(filterName: name, to: input)
            let cgImage = context.createCGImage(output, from: output.extent)
            XCTAssertNotNil(cgImage, "Filter '\(name)' failed to render to CGImage")
        }
    }
}
