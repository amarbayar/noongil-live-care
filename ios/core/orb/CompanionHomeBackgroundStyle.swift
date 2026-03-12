import SwiftUI

struct CompanionHomeBackgroundStyle: Equatable {
    let top: OrbTone
    let middle: OrbTone
    let bottom: OrbTone
    let primaryText: OrbTone
    let secondaryText: OrbTone

    var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: top.color, location: 0.0),
                .init(color: middle.color, location: 0.40),
                .init(color: bottom.color, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func make(for state: OrbState) -> CompanionHomeBackgroundStyle {
        switch state {
        case .resting, .checkInDue, .complete:
            return CompanionHomeBackgroundStyle(
                top: tone("#00C6FF"),
                middle: tone("#4A54E1"),
                bottom: tone("#8E2DE2"),
                primaryText: tone("#FFFFFF"),
                secondaryText: tone("#FFFFFF", alpha: 0.72)
            )
        case .listening:
            return CompanionHomeBackgroundStyle(
                top: tone("#2193B0"),
                middle: tone("#4A54E1"),
                bottom: tone("#6DD5ED"),
                primaryText: tone("#FFFFFF"),
                secondaryText: tone("#FFFFFF", alpha: 0.74)
            )
        case .processing:
            return CompanionHomeBackgroundStyle(
                top: tone("#4B6CB7"),
                middle: tone("#4A54E1"),
                bottom: tone("#182848"),
                primaryText: tone("#FFFFFF"),
                secondaryText: tone("#FFFFFF", alpha: 0.74)
            )
        case .speaking:
            return CompanionHomeBackgroundStyle(
                top: tone("#FF758C"),
                middle: tone("#4A54E1"),
                bottom: tone("#FF7EB3"),
                primaryText: tone("#FFFFFF"),
                secondaryText: tone("#FFFFFF", alpha: 0.76)
            )
        case .error:
            return CompanionHomeBackgroundStyle(
                top: tone("#5B2333"),
                middle: tone("#3A274B"),
                bottom: tone("#191522"),
                primaryText: tone("#FFFFFF"),
                secondaryText: tone("#FFFFFF", alpha: 0.72)
            )
        }
    }

    private static func tone(_ hex: String, alpha: Double = 1.0) -> OrbTone {
        let components = CompanionHomeBackgroundHexColor(hex: hex)
        return OrbTone(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: alpha
        )
    }
}

private struct CompanionHomeBackgroundHexColor {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        let value = Int(sanitized, radix: 16) ?? 0
        red = Double((value >> 16) & 0xFF) / 255.0
        green = Double((value >> 8) & 0xFF) / 255.0
        blue = Double(value & 0xFF) / 255.0
    }
}
