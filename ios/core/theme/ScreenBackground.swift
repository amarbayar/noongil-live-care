import SwiftUI

struct ScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            CompanionHomeBackgroundStyle.make(for: .listening).gradient
                .ignoresSafeArea()
        )
    }
}

extension View {
    func screenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }
}
