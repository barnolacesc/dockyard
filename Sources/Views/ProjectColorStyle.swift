// ABOUTME: Maps persisted project color choices to localized labels and SwiftUI colors.
// ABOUTME: Keeps project color presentation consistent across expanded and collapsed sidebars.

import SwiftUI

extension ProjectColor {
    var localizedName: LocalizedStringKey {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}
