import Foundation

struct OrbRotationModel: Equatable {
    private(set) var anchorDegrees: Double
    private(set) var anchorTime: TimeInterval
    private(set) var duration: Double

    init(anchorDegrees: Double = 0.0, anchorTime: TimeInterval = 0.0, duration: Double) {
        self.anchorDegrees = anchorDegrees
        self.anchorTime = anchorTime
        self.duration = duration
    }

    func degrees(at time: TimeInterval, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 18.0 }
        guard duration > 0 else { return normalized(anchorDegrees) }

        let elapsed = time - anchorTime
        let revolutions = elapsed / duration
        return normalized(anchorDegrees + (revolutions * 360.0))
    }

    mutating func transition(toDuration newDuration: Double, at time: TimeInterval, reduceMotion: Bool = false) {
        anchorDegrees = degrees(at: time, reduceMotion: reduceMotion)
        anchorTime = time
        duration = newDuration
    }

    private func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360.0)
        return remainder >= 0 ? remainder : remainder + 360.0
    }
}
