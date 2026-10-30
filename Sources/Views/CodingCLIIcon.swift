// ABOUTME: Provider icons and view representations for Coding Agent LLMs (Claude, OpenAI, AGY, OpenCode, Pi).
// ABOUTME: Renders brand template vector icons with optional brand coloring or monochrome tinting.

import SwiftUI

extension CodingCLI {
    var iconAssetName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "openai"
        case .agy: return "agy"
        case .opencode: return "opencode"
        case .pi: return "pi"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34) // Anthropic terracotta
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50) // OpenAI emerald
        case .agy: return Color(red: 0.19, green: 0.53, blue: 1.00) // Google Antigravity blue
        case .opencode: return Color(red: 0.55, green: 0.36, blue: 0.96) // OpenCode purple
        case .pi: return Color(red: 0.94, green: 0.56, blue: 0.51) // Pi coral (#F09082)
        }
    }
}

struct CodingCLIIcon: View {
    let cli: CodingCLI
    var size: CGFloat = 11
    var useBrandColor: Bool = false

    var body: some View {
        Image(cli.iconAssetName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(useBrandColor ? AnyShapeStyle(cli.brandColor) : AnyShapeStyle(.secondary))
            .help(cli.displayName)
            .accessibilityLabel(cli.displayName)
    }
}
