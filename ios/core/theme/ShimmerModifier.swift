import SwiftUI

/// Animated shimmer effect for skeleton loading placeholders.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.4)
        } else {
            content
                .overlay(shimmerGradient.mask(content))
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 2.0
                    }
                }
        }
    }

    private var shimmerGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.08), location: phase - 0.4),
                .init(color: .white.opacity(0.28), location: phase),
                .init(color: .white.opacity(0.08), location: phase + 0.4)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
