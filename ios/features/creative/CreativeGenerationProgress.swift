import Foundation

struct CreativeGenerationProgress: Equatable {
    enum Stage: String, Equatable {
        case starting
        case queued
        case polling
        case downloading
        case finalizing
        case retrying
    }

    let stage: Stage
    let message: String
    let fraction: Double?

    init(
        stage: Stage,
        message: String,
        fraction: Double? = nil
    ) {
        self.stage = stage
        self.message = message
        self.fraction = fraction
    }
}
