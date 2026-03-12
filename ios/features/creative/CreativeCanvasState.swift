import Foundation

struct CreativeCanvasState: Equatable {
    enum Status: String, Equatable {
        case clarifying
        case generating
        case streaming
        case ready
        case failed
        case cancelled
    }

    enum MediaAction: Equatable {
        // Transport
        case play, pause, replay, seekForward, seekBackward, stop
        case volumeUp, volumeDown, mute
        case speed(Double)
        case loop
        // Image transform
        case rotateLeft, rotateRight
        case zoomIn, zoomOut, zoomReset
        // Navigation
        case next, previous
        // Lifecycle
        case delete, save
        // Display
        case fullscreen, exitFullscreen
    }

    let artifactId: String
    var mediaType: CreativeMediaType
    var prompt: String
    var status: Status
    var statusMessage: String
    var progressFraction: Double?
    var progressDetail: String?
    var result: CreativeResult?
    var isVisible: Bool
    var playbackToken: UUID = UUID()
    var pendingMediaAction: MediaAction?
    var mediaActionToken: UUID = UUID()

    // Image transform state
    var imageRotationDegrees: Double = 0
    var imageZoomScale: CGFloat = 1.0

    // Display state
    var isFullscreen: Bool = false

    var title: String {
        switch status {
        case .clarifying:
            return "Shaping your idea"
        case .generating:
            return generatingTitle
        case .streaming:
            return "Streaming music"
        case .ready:
            return readyTitle
        case .failed:
            return "I hit a snag"
        case .cancelled:
            return "Stopped"
        }
    }

    var subtitle: String {
        if let progressDetail, !progressDetail.isEmpty {
            return "\(statusMessage) \(progressDetail)"
        }
        return statusMessage
    }

    var referenceSummary: String {
        let visibility = isVisible ? "visible" : "hidden"
        return "Current canvas: \(mediaType.rawValue) (\(visibility)) based on prompt: \(prompt)"
    }

    private var generatingTitle: String {
        switch mediaType {
        case .image:
            return "Drawing your image"
        case .video:
            return "Animating your video"
        case .music:
            return "Composing your music"
        case .animation:
            return "Building your animation"
        }
    }

    private var readyTitle: String {
        switch mediaType {
        case .image:
            return "Image ready"
        case .video:
            return "Video ready"
        case .music:
            return "Music ready"
        case .animation:
            return "Animation ready"
        }
    }
}
