import AppKit
import SwiftUI

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum DesignColor {
    static let brandAccent = Color(light: .systemOrange, dark: .systemOrange)
    static let statusSuccess = Color(light: .systemGreen, dark: .systemGreen)
    static let statusWarning = Color(light: .systemYellow, dark: .systemYellow)
    static let statusError = Color(light: .systemRed, dark: .systemRed)
    static let statusInfo = Color(light: .systemBlue, dark: .systemBlue)
    static let statusMerged = Color(light: .systemPurple, dark: .systemPurple)
}
