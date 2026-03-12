import Foundation

struct CompanionHomeOrbChrome {
    static func shouldShowStatusRing(isSessionActive: Bool, state: OrbState) -> Bool {
        !isSessionActive && state == .checkInDue
    }

    static func isTapEnabled(canStartSession: Bool, isSessionActive: Bool) -> Bool {
        canStartSession || isSessionActive
    }

    static func orbOpacity(canStartSession: Bool, isSessionActive: Bool) -> Double {
        isTapEnabled(canStartSession: canStartSession, isSessionActive: isSessionActive) ? 1.0 : 0.55
    }

    static func orbScale(
        isPressed: Bool,
        canStartSession: Bool,
        isSessionActive: Bool
    ) -> Double {
        guard isPressed, isTapEnabled(canStartSession: canStartSession, isSessionActive: isSessionActive) else {
            return 1.0
        }
        return 0.965
    }
}
