import SwiftUI

/// Dynamic theme loaded from bundled JSON. Designed for future Firestore swap-in.
@MainActor
final class ThemeService: ObservableObject {

    // MARK: - Colors

    @Published var background: Color = Color(hex: "#F8FAFC")
    @Published var surface: Color = Color(hex: "#FFFFFF")
    @Published var primary: Color = Color(hex: "#2563EB")
    @Published var secondary: Color = Color(hex: "#059669")
    @Published var accent: Color = Color(hex: "#0EA5E9")
    @Published var text: Color = Color(hex: "#1E293B")
    @Published var textSecondary: Color = Color(hex: "#64748B")
    @Published var success: Color = Color(hex: "#059669")
    @Published var warning: Color = Color(hex: "#D97706")
    @Published var error: Color = Color(hex: "#DC2626")
    @Published var orbGlow: Color = Color(hex: "#2563EB")
    @Published var orbIdle: Color = Color(hex: "#059669")
    @Published var orbGold: Color = Color(hex: "#0EA5E9")
    @Published var ambientMorning: Color = Color(hex: "#EFF6FF")
    @Published var ambientEvening: Color = Color(hex: "#F0FDF4")
    @Published var auroraPurple: Color = Color(hex: "#93C5FD")
    @Published var auroraTeal: Color = Color(hex: "#6EE7B7")
    @Published var auroraPink: Color = Color(hex: "#BAE6FD")

    // MARK: - Typography

    @Published var titleSize: CGFloat = 28
    @Published var bodySize: CGFloat = 18
    @Published var captionSize: CGFloat = 14

    // MARK: - Animation

    @Published var orbPulseSpeed: Double = 2.0
    @Published var transitionDuration: Double = 0.3

    // MARK: - Glass

    @Published var glassBorderWidth: CGFloat = 1
    @Published var glassGlowRadius: CGFloat = 0
    @Published var glassGlowOpacity: Double = 0
    @Published var glassShadowRadius: CGFloat = 12
    @Published var glassShadowOffsetY: CGFloat = 4
    @Published var glassShadowOpacity: Double = 0.08
    @Published var glassSpecularOpacity: Double = 0
    @Published var glassAnimationSpeed: Double = 12.0
    @Published var glassBackgroundOpacity: Double = 1.0

    // MARK: - Init

    init() {
        loadBundledTheme()
    }

    // MARK: - Load from Bundle

    func loadBundledTheme() {
        guard let url = Bundle.main.url(
            forResource: "theme-default",
            withExtension: "json",
            subdirectory: "config"
        ) else {
            print("[ThemeService] theme-default.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[ThemeService] Failed to parse theme-default.json")
                return
            }
            applyTheme(dict)
        } catch {
            print("[ThemeService] Error loading theme-default.json: \(error)")
        }
    }

    // MARK: - Apply (future Firestore hook)

    func applyTheme(_ dict: [String: Any]) {
        if let colors = dict["colors"] as? [String: String] {
            if let v = colors["background"] { background = Color(hex: v) }
            if let v = colors["surface"] { surface = Color(hex: v) }
            if let v = colors["primary"] { primary = Color(hex: v) }
            if let v = colors["secondary"] { secondary = Color(hex: v) }
            if let v = colors["accent"] { accent = Color(hex: v) }
            if let v = colors["text"] { text = Color(hex: v) }
            if let v = colors["textSecondary"] { textSecondary = Color(hex: v) }
            if let v = colors["success"] { success = Color(hex: v) }
            if let v = colors["warning"] { warning = Color(hex: v) }
            if let v = colors["error"] { error = Color(hex: v) }
            if let v = colors["orbGlow"] { orbGlow = Color(hex: v) }
            if let v = colors["orbIdle"] { orbIdle = Color(hex: v) }
            if let v = colors["orbGold"] { orbGold = Color(hex: v) }
            if let v = colors["ambientMorning"] { ambientMorning = Color(hex: v) }
            if let v = colors["ambientEvening"] { ambientEvening = Color(hex: v) }
            if let v = colors["auroraPurple"] { auroraPurple = Color(hex: v) }
            if let v = colors["auroraTeal"] { auroraTeal = Color(hex: v) }
            if let v = colors["auroraPink"] { auroraPink = Color(hex: v) }
        }

        if let typography = dict["typography"] as? [String: Any] {
            if let v = typography["titleSize"] as? Double { titleSize = CGFloat(v) }
            if let v = typography["bodySize"] as? Double { bodySize = CGFloat(v) }
            if let v = typography["captionSize"] as? Double { captionSize = CGFloat(v) }
        }

        if let animation = dict["animation"] as? [String: Any] {
            if let v = animation["orbPulseSpeed"] as? Double { orbPulseSpeed = v }
            if let v = animation["transitionDuration"] as? Double { transitionDuration = v }
        }

        if let glass = dict["glass"] as? [String: Any] {
            if let v = glass["borderWidth"] as? Double { glassBorderWidth = CGFloat(v) }
            if let v = glass["glowRadius"] as? Double { glassGlowRadius = CGFloat(v) }
            if let v = glass["glowOpacity"] as? Double { glassGlowOpacity = v }
            if let v = glass["shadowRadius"] as? Double { glassShadowRadius = CGFloat(v) }
            if let v = glass["shadowOffsetY"] as? Double { glassShadowOffsetY = CGFloat(v) }
            if let v = glass["shadowOpacity"] as? Double { glassShadowOpacity = v }
            if let v = glass["specularOpacity"] as? Double { glassSpecularOpacity = v }
            if let v = glass["animationSpeed"] as? Double { glassAnimationSpeed = v }
            if let v = glass["backgroundOpacity"] as? Double { glassBackgroundOpacity = v }
        }
    }
}
