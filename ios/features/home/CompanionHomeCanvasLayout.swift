import Foundation

struct CompanionHomeCanvasLayout: Equatable {
    enum OrbMode: Equatable {
        case centeredLarge
        case dockedCompact
    }

    let showsCanvasOverlay: Bool
    let orbMode: OrbMode
    let showsHistory: Bool

    static func make(canvas: CreativeCanvasState?) -> CompanionHomeCanvasLayout {
        guard let canvas, canvas.isVisible else {
            return CompanionHomeCanvasLayout(
                showsCanvasOverlay: false,
                orbMode: .centeredLarge,
                showsHistory: true
            )
        }

        return CompanionHomeCanvasLayout(
            showsCanvasOverlay: true,
            orbMode: .dockedCompact,
            showsHistory: false
        )
    }
}
