import UIKit

struct CreativeResult: Equatable {
    var mediaType: CreativeMediaType {
        didSet { touchRevision() }
    }
    var image: UIImage? {
        didSet { touchRevision() }
    }
    var videoURL: URL? {
        didSet { touchRevision() }
    }
    var audioData: Data? {
        didSet { touchRevision() }
    }
    var composedVideoURL: URL? {
        didSet { touchRevision() }
    }
    var prompt: String {
        didSet { touchRevision() }
    }
    private(set) var revision = UUID()

    init(
        mediaType: CreativeMediaType,
        image: UIImage? = nil,
        videoURL: URL? = nil,
        audioData: Data? = nil,
        composedVideoURL: URL? = nil,
        prompt: String
    ) {
        self.mediaType = mediaType
        self.image = image
        self.videoURL = videoURL
        self.audioData = audioData
        self.composedVideoURL = composedVideoURL
        self.prompt = prompt
    }

    var resolvedMediaType: CreativeMediaType {
        if playbackVideoURL != nil {
            return mediaType == .animation ? .animation : .video
        }
        if audioData != nil {
            return .music
        }
        if image != nil {
            return .image
        }
        return mediaType
    }

    var playbackVideoURL: URL? {
        composedVideoURL ?? videoURL
    }

    var shouldPlaySeparateAudioTrack: Bool {
        mediaType == .animation && composedVideoURL == nil && videoURL != nil && audioData != nil
    }

    static func == (lhs: CreativeResult, rhs: CreativeResult) -> Bool {
        lhs.revision == rhs.revision
    }

    private mutating func touchRevision() {
        revision = UUID()
    }
}
