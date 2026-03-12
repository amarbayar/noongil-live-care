import XCTest

@MainActor
final class UnifiedSessionCompletionCoordinatorTests: XCTestCase {

    func testFinish_stopsOnlyAfterToolResponseFlushes() async {
        var stopCalled = false
        var completionRan = false
        var sentSuccess = false

        let coordinator = UnifiedSessionCompletionCoordinator(
            sendToolResponse: { _, response, completion in
                XCTAssertTrue(completionRan)
                XCTAssertFalse(stopCalled)
                sentSuccess = response["success"] as? Bool == true
                completion()
            },
            stopSession: {
                stopCalled = true
            }
        )

        await coordinator.finish(id: "tool-1") {
            completionRan = true
        }

        XCTAssertTrue(sentSuccess)
        XCTAssertTrue(stopCalled)
    }

    func testFinish_stopsEvenWithoutAdditionalCompletionWork() async {
        var stopCalled = false

        let coordinator = UnifiedSessionCompletionCoordinator(
            sendToolResponse: { _, _, completion in
                XCTAssertFalse(stopCalled)
                completion()
            },
            stopSession: {
                stopCalled = true
            }
        )

        await coordinator.finish(id: "tool-2") {}

        XCTAssertTrue(stopCalled)
    }
}
