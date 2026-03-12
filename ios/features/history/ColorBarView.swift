import SwiftUI

/// Animated horizontal bar showing mood score (1–5) with color-coded fill.
struct MoodColorBar: View {
    let score: Int

    @State private var animatedFraction: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: CGFloat {
        CGFloat(max(1, min(5, score))) / 5.0
    }

    private var fillColor: Color {
        switch score {
        case 1: return Color(hex: "#DC2626")
        case 2: return Color(hex: "#D97706")
        case 3: return Color(hex: "#D97706")
        case 4: return Color(hex: "#059669")
        case 5: return Color(hex: "#059669")
        default: return Color(hex: "#D97706")
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#1E293B").opacity(0.08))

                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: geo.size.width * animatedFraction)
            }
        }
        .frame(height: 8)
        .onAppear {
            if reduceMotion {
                animatedFraction = fraction
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedFraction = fraction
                }
            }
        }
        .accessibilityLabel("Mood \(score) out of 5")
    }
}

/// Animated horizontal bar showing sleep hours with color-coded fill.
struct SleepColorBar: View {
    let hours: Double

    @State private var animatedFraction: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: CGFloat {
        min(1.0, CGFloat(max(0, hours)) / 10.0)
    }

    private var fillColor: Color {
        switch hours {
        case ..<5: return Color(hex: "#DC2626")
        case 5..<7: return Color(hex: "#D97706")
        default: return Color(hex: "#059669")
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#1E293B").opacity(0.08))

                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: geo.size.width * animatedFraction)
            }
        }
        .frame(height: 8)
        .onAppear {
            if reduceMotion {
                animatedFraction = fraction
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedFraction = fraction
                }
            }
        }
        .accessibilityLabel("\(String(format: "%.0f", hours)) hours of sleep")
    }
}
