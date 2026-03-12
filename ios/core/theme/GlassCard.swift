import SwiftUI

/// Clean card modifier: white background, thin border, soft shadow.
/// Uses native Liquid Glass on iOS 26+, falls back to solid surface on older versions.
struct GlassCardModifier: ViewModifier {
    @EnvironmentObject var theme: ThemeService
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .padding(16)
                .background(theme.surface)
                .cornerRadius(cornerRadius)
                .padding(.horizontal)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26, *) {
                content
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .padding(.horizontal)
            } else {
                frostedGlass(content)
            }
            #else
            frostedGlass(content)
            #endif
        }
    }

    @ViewBuilder
    private func frostedGlass(_ content: Content) -> some View {
        content
            .padding(16)
            .background(theme.surface)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.text.opacity(0.08), lineWidth: theme.glassBorderWidth)
            )
            .shadow(
                color: .black.opacity(theme.glassShadowOpacity),
                radius: theme.glassShadowRadius,
                y: theme.glassShadowOffsetY
            )
            .padding(.horizontal)
    }
}

/// Inline glass modifier for elements that don't need card padding/margins (list rows, buttons, badges).
struct InlineGlassModifier: ViewModifier {
    @EnvironmentObject var theme: ThemeService
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(theme.surface)
                .cornerRadius(cornerRadius)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26, *) {
                content
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                frostedInline(content)
            }
            #else
            frostedInline(content)
            #endif
        }
    }

    @ViewBuilder
    private func frostedInline(_ content: Content) -> some View {
        content
            .background(theme.surface)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.text.opacity(0.08), lineWidth: theme.glassBorderWidth)
            )
    }
}

/// Helper for list row glass backgrounds where a View modifier can't be used directly.
enum GlassCard {
    @ViewBuilder
    static func listRowBackground(cornerRadius: CGFloat = 10) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            fallbackListRow(cornerRadius: cornerRadius)
        }
        #else
        fallbackListRow(cornerRadius: cornerRadius)
        #endif
    }

    @ViewBuilder
    private static func fallbackListRow(cornerRadius: CGFloat) -> some View {
        Color.white
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(hex: "#1E293B").opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func inlineGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(InlineGlassModifier(cornerRadius: cornerRadius))
    }
}
