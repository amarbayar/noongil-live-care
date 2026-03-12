import Foundation

enum OrbHTMLState: String, Equatable {
    case neutral
    case listening
    case thinking
    case speaking
}

extension OrbState {
    var htmlState: OrbHTMLState {
        switch self {
        case .resting, .complete, .checkInDue, .error:
            return .neutral
        case .listening:
            return .listening
        case .processing:
            return .thinking
        case .speaking:
            return .speaking
        }
    }
}
