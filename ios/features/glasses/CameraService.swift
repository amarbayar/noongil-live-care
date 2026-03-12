import Foundation
import UIKit
import Combine
import MWDATCore
import MWDATCamera

/// Wraps MWDATCamera for video streaming from glasses and frame capture for Gemini vision.
@MainActor
final class CameraService: ObservableObject {
    @Published var streamState: StreamSessionState = .stopped
    @Published var latestFrame: UIImage?
    @Published var errorMessage: String?

    private var streamSession: StreamSession?
    private var stateToken: (any AnyListenerToken)?
    private var frameToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?
    private var photoToken: (any AnyListenerToken)?

    /// Continuation for async photo capture
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    /// Start the camera stream session.
    /// IMPORTANT: Call this AFTER AudioService has configured HFP (wait ~2s).
    func startStream() async {
        guard streamSession == nil else { return }

        let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low, // 360x640, saves bandwidth for audio
            frameRate: 15
        )

        let session = StreamSession(
            streamSessionConfig: config,
            deviceSelector: deviceSelector
        )
        streamSession = session

        // Listen to state changes
        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                print("[CameraService] State: \(state)")
                self?.streamState = state
            }
        }

        // Listen to video frames — keep only latest
        frameToken = session.videoFramePublisher.listen { [weak self] (frame: VideoFrame) in
            guard let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self?.latestFrame = image
            }
        }

        // Listen to errors — surface to UI
        errorToken = session.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                let msg = Self.describeError(error)
                print("[CameraService] Error: \(msg)")
                self?.errorMessage = msg
            }
        }

        // Listen for photo captures
        photoToken = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                print("[CameraService] Photo captured (\(photoData.data.count) bytes)")
                let image = UIImage(data: photoData.data)
                // If someone is awaiting a photo, deliver it
                if let continuation = self?.photoContinuation {
                    self?.photoContinuation = nil
                    continuation.resume(returning: image)
                }
            }
        }

        // Check camera permission before starting
        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            print("[CameraService] Camera permission: \(status)")
            if status == .denied {
                errorMessage = "Camera permission denied. Tap 'Grant Camera Access' in Setup tab."
                return
            }
        } catch {
            print("[CameraService] Permission check failed: \(error) — attempting stream anyway")
        }

        print("[CameraService] Starting stream...")
        await session.start()
        print("[CameraService] start() returned, state: \(session.state)")
    }

    /// Stop the camera stream.
    func stopStream() async {
        guard let session = streamSession else { return }
        print("[CameraService] Stopping stream...")
        await session.stop()
        stateToken = nil
        frameToken = nil
        errorToken = nil
        photoToken = nil
        photoContinuation = nil
        streamSession = nil
        streamState = .stopped
        latestFrame = nil
        errorMessage = nil
    }

    /// Capture the current frame for Gemini vision requests.
    /// Returns the latest stream frame, or nil if not streaming.
    func captureCurrentFrame() -> UIImage? {
        return latestFrame
    }

    /// Capture a high-quality photo via the glasses camera.
    /// Falls back to the latest stream frame if capture fails.
    func capturePhoto() async -> UIImage? {
        guard let session = streamSession, streamState == .streaming else {
            print("[CameraService] capturePhoto: not streaming, using latestFrame")
            return latestFrame
        }

        // Use async continuation to await the photo from the publisher
        let image: UIImage? = await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let success = session.capturePhoto(format: .jpeg)
            print("[CameraService] capturePhoto triggered, success=\(success)")

            if !success {
                // Capture failed, fall back to latest frame
                self.photoContinuation = nil
                continuation.resume(returning: self.latestFrame)
            }
        }

        return image ?? latestFrame
    }

    /// Capture current frame as JPEG data for Gemini API.
    func captureCurrentFrameAsJPEG(quality: CGFloat = 0.7) -> Data? {
        return latestFrame?.jpegData(compressionQuality: quality)
    }

    /// Whether the stream is active and frames are available
    var isStreaming: Bool {
        streamState == .streaming
    }

    // MARK: - Error Descriptions

    private static func describeError(_ error: StreamSessionError) -> String {
        switch error {
        case .hingesClosed:
            return "Glasses hinges are closed. Open them to use the camera."
        case .permissionDenied:
            return "Camera permission denied. Grant camera access in Meta AI app."
        case .timeout:
            return "Camera stream timed out. Try reconnecting glasses."
        case .deviceNotFound(let id):
            return "Device not found: \(id). Reconnect glasses."
        case .deviceNotConnected(let id):
            return "Device disconnected: \(id). Reconnect glasses."
        case .videoStreamingError:
            return "Video streaming error. Try stopping and restarting."
        case .audioStreamingError:
            return "Audio streaming error. Check Bluetooth connection."
        case .internalError:
            return "Internal camera error. Try restarting the session."
        @unknown default:
            return "Unknown camera error: \(error)"
        }
    }
}
