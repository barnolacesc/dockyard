// ABOUTME: Passive tour of Dockyard's keyboard, usage, persistence, and archive features.
// ABOUTME: Every step is manual so the tour never mutates workstreams or launches commands.

import Foundation

enum PowerFeaturesFlow {
    static let id = "power-features"

    @MainActor
    static func make() -> TourFlow {
        TourFlow(id: id, steps: [
            TourStep(
                id: "overview",
                anchor: nil,
                titleKey: "Work faster without losing context",
                bodyKey: "This passive tour highlights Dockyard's power features. It will not run commands, change settings, or modify your workstreams.",
                advance: .manual
            ),
            TourStep(
                id: "shortcut-hints",
                anchor: .workspaceTabBar,
                titleKey: "Hold Command for shortcut hints",
                bodyKey: "Hold ⌘ to reveal available shortcuts on visible controls. Nothing runs until you choose a command.",
                advance: .manual
            ),
            TourStep(
                id: "usage-meters",
                anchor: .sidebarStatusStrip,
                titleKey: "Track local agent usage",
                bodyKey: "The sidebar meter shows locally available Claude Code or Codex usage. Use its arrows to switch providers, or click the meter to refresh.",
                advance: .manual
            ),
            TourStep(
                id: "tmux-persistence",
                anchor: .agentTab,
                titleKey: "Resume Coding Agent sessions",
                bodyKey: "When tmux mode is enabled, Dockyard reconnects to this workstream's Coding Agent session after you quit and reopen the app.",
                advance: .manual
            ),
            TourStep(
                id: "safe-archive",
                anchor: .selectedWorkstreamRow,
                titleKey: "Remove without deleting work",
                bodyKey: "Remove is Dockyard's archive action: it stops terminals and hides the workstream while keeping its worktree and branch. Purge is the separate destructive action.",
                advance: .manual
            ),
            TourStep(
                id: "done",
                anchor: nil,
                titleKey: "Power features, on your terms",
                bodyKey: "Press ⌘/ for the complete shortcut reference. Settings lets you choose shortcut hints, tmux mode, and usage options.",
                advance: .manual
            ),
        ])
    }
}
