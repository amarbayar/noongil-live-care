import Foundation

enum CreativeMediaType: String, Codable {
    case image, video, music, animation
}

enum CreativeAspect: String, CaseIterable {
    case subject, mood, style, composition, colorPalette
    case motion, duration
    case tempo, instruments

    static func aspects(for type: CreativeMediaType) -> [CreativeAspect] {
        switch type {
        case .image:
            return [.subject, .mood, .style, .composition, .colorPalette]
        case .video:
            return [.subject, .mood, .style, .motion, .duration, .colorPalette]
        case .music:
            return [.mood, .style, .tempo, .instruments]
        case .animation:
            return [.subject, .mood, .style, .motion, .duration, .colorPalette, .tempo, .instruments]
        }
    }
}

struct CreativeBrief {
    var mediaType: CreativeMediaType
    var clarifiedAspects: [CreativeAspect: String] = [:]
    var round: Int = 0

    var requiredAspects: [CreativeAspect] {
        CreativeAspect.aspects(for: mediaType)
    }

    var unclarifiedAspects: [CreativeAspect] {
        requiredAspects.filter { clarifiedAspects[$0] == nil }
    }

    var allClarified: Bool {
        unclarifiedAspects.isEmpty
    }
}
