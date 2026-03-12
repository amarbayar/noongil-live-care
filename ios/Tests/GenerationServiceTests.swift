import XCTest

final class GenerationServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        GenerationServiceURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        GenerationServiceURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testGenerateMusic_appliesFirebaseAuthTokenBeforeCallingBackend() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationServiceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = BackendClient(
            baseURL: URL(string: "https://example.com")!,
            session: session
        )

        GenerationServiceURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = """
            {"audioBase64":"AQID","mimeType":"audio/wav"}
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let service = GenerationService(
            backendClient: client,
            authTokenProvider: { "test-token" }
        )
        let data = try await service.generateMusic(prompt: "gentle rain", negativePrompt: nil)

        XCTAssertEqual(data, Data([0x01, 0x02, 0x03]))
    }

    func testGenerateImageWithReference_parsesInlineDataResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationServiceURLProtocol.self]
        let session = URLSession(configuration: configuration)

        // Create a tiny 1x1 red PNG for response
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let testImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let testImageData = testImage.pngData()!
        let base64Image = testImageData.base64EncodedString()

        GenerationServiceURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            XCTAssertTrue(url.contains("gemini-3.1-flash-image-preview"))
            XCTAssertTrue(url.contains("generateContent"))

            let body = """
            {"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\(base64Image)"}}]}}]}
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let service = GenerationService(session: session)
        let refImage = UIImage(systemName: "camera")!
        let result = try await service.generateImageWithReference(
            prompt: "transform this into a painting",
            referenceImage: refImage
        )

        XCTAssertNotNil(result)
    }

    func testGenerateVideo_reportsProgressAndCompletes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationServiceURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var pollCount = 0
        GenerationServiceURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString

            if url.contains("predictLongRunning") {
                let body = #"{"name":"operations/video-123"}"#
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(body.utf8))
            }

            if url.contains("operations/video-123") {
                pollCount += 1
                let body: String
                if pollCount < 3 {
                    body = #"{"done":false}"#
                } else {
                    body = #"{"done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://example.com/generated.mp4"}}]}}}"#
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(body.utf8))
            }

            if url.contains("generated.mp4") {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "video/mp4"]
                )!
                return (response, Data([0x00, 0x01, 0x02]))
            }

            throw NSError(domain: "GenerationServiceURLProtocol", code: 404)
        }

        let service = GenerationService(
            session: session,
            videoPollIntervalNanoseconds: 1_000_000,
            videoMaxAttempts: 4
        )
        var progressUpdates: [CreativeGenerationProgress] = []

        let url = try await service.generateVideo(
            prompt: "animate the sunset",
            aspectRatio: "16:9",
            durationSeconds: nil,
            startingImage: nil,
            onProgress: { progressUpdates.append($0) }
        )

        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertTrue(progressUpdates.contains(where: { $0.stage == .queued }))
        XCTAssertTrue(progressUpdates.contains(where: { $0.stage == .polling }))
        XCTAssertTrue(progressUpdates.contains(where: { $0.stage == .downloading }))
    }

    func testGenerateVideo_timesOutAfterConfiguredAttempts() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationServiceURLProtocol.self]
        let session = URLSession(configuration: configuration)

        GenerationServiceURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString

            if url.contains("predictLongRunning") {
                let body = #"{"name":"operations/video-timeout"}"#
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(body.utf8))
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"done":false}"#.utf8))
        }

        let service = GenerationService(
            session: session,
            videoPollIntervalNanoseconds: 1_000_000,
            videoMaxAttempts: 2
        )

        do {
            _ = try await service.generateVideo(
                prompt: "long render",
                aspectRatio: "16:9",
                durationSeconds: nil,
                startingImage: nil,
                onProgress: nil
            )
            XCTFail("Expected timeout")
        } catch let error as GenerationService.GenerationError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class GenerationServiceURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "GenerationServiceURLProtocol", code: 1))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
