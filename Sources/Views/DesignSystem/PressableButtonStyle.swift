import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.96
    var staticScale = false

    func makeBody(configuration: Configuration) -> some View {
        let active = configuration.isPressed && !staticScale && !reduceMotion

        return configuration.label
            .scaleEffect(active ? pressedScale : 1)
            .animation(reduceMotion ? nil : DesignMotion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension View {
    func pressable(scale: CGFloat = 0.96, static isStatic: Bool = false) -> some View {
        buttonStyle(PressableButtonStyle(pressedScale: scale, staticScale: isStatic))
    }
}
