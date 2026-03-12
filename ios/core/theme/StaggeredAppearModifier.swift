import SwiftUI

/// Fade-in + slide-up modifier with per-item stagger delay.
/// Animates once on appear; respects Reduce Motion.
struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    let delay: Double

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isVisible ? 1.0 : 0.0)
            .offset(y: reduceMotion || isVisible ? 0 : 20)
            .onAppear {
                guard !reduceMotion else { isVisible = true; return }
                withAnimation(.easeOut(duration: 0.5).delay(Double(index) * delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int, delay: Double = 0.05) -> some View {
        modifier(StaggeredAppearModifier(index: index, delay: delay))
    }
}
