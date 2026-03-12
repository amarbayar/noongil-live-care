import AVFoundation
import CoreImage
import UIKit

@MainActor
final class PhoneCameraService: NSObject, ObservableObject {
    enum CameraPosition: String {
        case front, back
    }

    // MARK: - Published State

    @Published var isRunning = false
    @Published var currentPosition: CameraPosition = .back
    @Published var currentFilter: String = "none"
    @Published var latestFilteredImage: UIImage?

    // MARK: - Internals

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "ai.noongil.phonecamera", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Thread-safe copy of currentFilter for use in nonisolated delegate callbacks.
    nonisolated(unsafe) private var activeFilterName: String = "none"

    private var currentInput: AVCaptureDeviceInput?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    // MARK: - Tool Declarations

    static let toolDeclarations: [[String: Any]] = [
        [
            "name": "take_photo",
            "description": "Take a photo using the iPhone camera. Use this when the user asks to take a photo, selfie, or picture. Returns the captured image.",
            "parameters": [
                "type": "object",
                "properties": [
                    "camera": [
                        "type": "string",
                        "enum": ["front", "back"],
                        "description": "Which camera to use. Use 'front' for selfies, 'back' for everything else."
                    ],
                    "filter": [
                        "type": "string",
                        "enum": CameraFilterPipeline.availableFilters,
                        "description": "Optional filter to apply before capture."
                    ]
                ],
                "required": ["camera"]
            ]
        ],
        [
            "name": "apply_filter",
            "description": "Apply a visual filter to the live camera preview. Use when the user asks to change how the camera looks.",
            "parameters": [
                "type": "object",
                "properties": [
                    "filter": [
                        "type": "string",
                        "enum": CameraFilterPipeline.availableFilters,
                        "description": "The filter name to apply."
                    ]
                ],
                "required": ["filter"]
            ]
        ]
    ]

    // MARK: - Lifecycle

    func start(position: CameraPosition) async {
        guard !isRunning else { return }

        let authorized = await requestCameraAccess()
        guard authorized else {
            print("[PhoneCameraService] Camera access denied")
            return
        }

        currentPosition = position
        configureCaptureSession(position: position)

        processingQueue.async { [weak self] in
            self?.session.startRunning()
        }
        isRunning = true
        print("[PhoneCameraService] Started with \(position.rawValue) camera")
    }

    func stop() {
        guard isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        isRunning = false
        latestFilteredImage = nil
        print("[PhoneCameraService] Stopped")
    }

    func switchCamera(to position: CameraPosition) async {
        guard position != currentPosition else { return }
        stop()
        await start(position: position)
    }

    func setFilter(_ name: String) {
        let resolved = CameraFilterPipeline.availableFilters.contains(name) ? name : "none"
        currentFilter = resolved
        activeFilterName = resolved
    }

    // MARK: - Capture

    func capturePhoto() async -> UIImage? {
        guard isRunning else { return nil }

        return await withCheckedContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func captureCurrentFrame() -> UIImage? {
        latestFilteredImage
    }

    func captureCurrentFrameAsJPEG(quality: CGFloat = 0.8) -> Data? {
        latestFilteredImage?.jpegData(compressionQuality: quality)
    }

    // MARK: - Private

    private func requestCameraAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func configureCaptureSession(position: CameraPosition) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Remove existing input
        if let existing = currentInput {
            session.removeInput(existing)
        }

        // Camera device
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("[PhoneCameraService] Failed to get camera device for \(position.rawValue)")
            return
        }

        guard session.canAddInput(input) else { return }
        session.addInput(input)
        currentInput = input

        // Video output (for live preview + filter)
        if !session.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
        }

        // Mirror front camera + set portrait orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = position == .front
            connection.videoOrientation = .portrait
        }

        // Photo output
        if !session.outputs.contains(photoOutput) {
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
        }

        if let photoConnection = photoOutput.connection(with: .video) {
            photoConnection.isVideoMirrored = position == .front
            photoConnection.videoOrientation = .portrait
        }

        // Session preset
        session.sessionPreset = .photo
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PhoneCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let filtered = CameraFilterPipeline.apply(filterName: activeFilterName, to: ciImage)

        guard let cgImage = ciContext.createCGImage(filtered, from: filtered.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        Task { @MainActor [weak self] in
            self?.latestFilteredImage = uiImage
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhoneCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            print("[PhoneCameraService] Photo capture error: \(error)")
            Task { @MainActor [weak self] in
                self?.photoContinuation?.resume(returning: nil)
                self?.photoContinuation = nil
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor [weak self] in
                self?.photoContinuation?.resume(returning: nil)
                self?.photoContinuation = nil
            }
            return
        }

        // Apply current filter to captured photo.
        // Use cgImage directly (no orientation transform) so the filter processes raw pixels,
        // then re-apply the original orientation to the output.
        let ciInput = CIImage(cgImage: image.cgImage!)
        let filtered = CameraFilterPipeline.apply(filterName: activeFilterName, to: ciInput)
        let context = CIContext()
        let finalImage: UIImage
        if let cgImage = context.createCGImage(filtered, from: filtered.extent) {
            finalImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        } else {
            finalImage = image
        }

        Task { @MainActor [weak self] in
            self?.photoContinuation?.resume(returning: finalImage)
            self?.photoContinuation = nil
        }
    }
}
