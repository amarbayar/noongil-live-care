import Foundation

@MainActor
struct UnifiedSessionCompletionCoordinator {
    let sendToolResponse: (String, [String: Any], @escaping () -> Void) -> Void
    let stopSession: () -> Void

    func finish(
        id: String,
        completionWork: @escaping () async -> Void
    ) async {
        await completionWork()
        await withCheckedContinuation { continuation in
            sendToolResponse(id, ["success": true]) {
                continuation.resume()
            }
        }
        stopSession()
    }
}
