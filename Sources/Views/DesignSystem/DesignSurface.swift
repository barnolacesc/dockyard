import SwiftUI

extension View {
    func hoverHighlight(radius: CGFloat = DesignRadius.md) -> some View {
        modifier(HoverHighlight(radius: radius))
    }

    func tabularNumbers() -> some View {
        monospacedDigit()
    }

    func imageOutline(radius: CGFloat = DesignRadius.sm) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color(light: .black, dark: .white).opacity(0.1), lineWidth: 1)
        )
    }
}

private struct HoverHighlight: ViewModifier {
    let radius: CGFloat

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .animation(reduceMotion ? nil : DesignMotion.interaction, value: hovering)
            .onHover { hovering = $0 }
    }
}
