// ABOUTME: Hand-curated What's New content per release, newest first.
// ABOUTME: Authoring rule: every user-facing feature adds an entry to the release being cut.

import Foundation

enum WhatsNewCatalog {
    /// Newest first. The version string must match the release that ships it
    /// (release-please owns version numbers; adjust when the release PR is cut).
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "0.2.5", entries: [
            WhatsNewEntry(
                symbol: "arrow.triangle.branch",
                titleKey: "Auto-Rename for More Agents",
                bodyKey: "Codex and OpenCode now rename a new workstream branch from your first task, just like Claude Code."
            ),
            WhatsNewEntry(
                symbol: "rectangle.bottomthird.inset.filled",
                titleKey: "Passive Notices",
                bodyKey: "Script reviews and source updates now appear as dismissible notices instead of interrupting your work."
            ),
            WhatsNewEntry(
                symbol: "terminal",
                titleKey: "Project Terminal",
                bodyKey: "Open a persistent terminal at the project root directly from the project row."
            ),
            WhatsNewEntry(
                symbol: "mic.fill",
                titleKey: "Mac Dictation in Terminals",
                bodyKey: "Press your Mac's Dictation key to speak in Agent and Terminal tabs, just like in standalone Ghostty."
            ),
            WhatsNewEntry(
                symbol: "arrow.triangle.branch",
                titleKey: "Branch from a Workstream",
                bodyKey: "Start a new workstream from any existing workstream branch while keeping the default one-click path."
            ),
            WhatsNewEntry(
                symbol: "paintpalette.fill",
                titleKey: "Project Colors",
                bodyKey: "Assign colors from a project's shortcut menu to make busy sidebars easier to scan."
            ),
            WhatsNewEntry(
                symbol: "bell.badge.fill",
                titleKey: "Agent Attention",
                bodyKey: "A focused inbox collects waiting, completed, and inactive Coding Agent updates across workstreams."
            ),
            WhatsNewEntry(
                symbol: "bolt.fill",
                titleKey: "Power Features",
                bodyKey: "Discover Dockyard's keyboard-first tools, usage meters, tmux persistence, and safe workstream cleanup in a passive tour.",
                tourFlowID: PowerFeaturesFlow.id
            ),
            WhatsNewEntry(
                symbol: "rectangle.3.group",
                titleKey: "Workspace Tabs Tour",
                bodyKey: "Learn how to open and switch terminals, browsers, and editors without leaving the keyboard.",
                tourFlowID: WorkspaceTabsFlow.id
            ),
            WhatsNewEntry(
                symbol: "sparkles",
                titleKey: "Interactive Tour",
                bodyKey: "A guided tour walks you through projects, workstreams, and the Coding Agent. Restart it anytime from the Help menu.",
                tourFlowID: GettingStartedFlow.id
            ),
            WhatsNewEntry(
                symbol: "megaphone",
                titleKey: "What's New Panel",
                bodyKey: "After each update, the highlights show up right here."
            ),
        ]),
    ]
}
