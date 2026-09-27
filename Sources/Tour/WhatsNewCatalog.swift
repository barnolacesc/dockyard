// ABOUTME: Hand-curated What's New content per release, newest first.
// ABOUTME: Authoring rule: every user-facing feature adds an entry to the release being cut.

import Foundation

enum WhatsNewCatalog {
    /// Newest first. The version string must match the release that ships it
    /// (release-please owns version numbers; adjust when the release PR is cut).
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "0.3.0", entries: [
            WhatsNewEntry(
                symbol: "globe.badge.chevron.backward",
                titleKey: "Agent-Controlled Browser",
                bodyKey: "Open a Chromium browser the Coding Agent can inspect and control while the regular in-app browser remains yours."
            ),
        ]),
        WhatsNewRelease(version: "0.2.6", entries: [
            WhatsNewEntry(
                symbol: "point.3.connected.trianglepath.dotted",
                titleKey: "Subagents in Sidebar and Tabs",
                bodyKey: "See active subagents invoked across your workspaces directly in the sidebar and on the Agent tab."
            ),
            WhatsNewEntry(
                symbol: "globe",
                titleKey: "Enhanced In-App Browser",
                bodyKey: "Logins and cache now persist across browser tabs and restarts. Choose whether links open in-app, in your external browser, or prompt you each time."
            ),
            WhatsNewEntry(
                symbol: "sparkles",
                titleKey: "Antigravity CLI Support",
                bodyKey: "Run Antigravity CLI (agy) in the Agent tab as a first-class coding agent."
            ),
            WhatsNewEntry(
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                titleKey: "Reliable Background Updates",
                bodyKey: "Dockyard now installs source updates without interrupting your work, confirms when they are ready, and shows the changelog after restart."
            ),
            WhatsNewEntry(
                symbol: "cup.and.saucer.fill",
                titleKey: "Caffeinate Mode",
                bodyKey: "Keep your Mac awake whenever Dockyard is open or only while a Coding Agent is actively working."
            ),
            WhatsNewEntry(
                symbol: "checkmark.circle",
                titleKey: "Pull Request Checks",
                bodyKey: "See CI progress on workstreams, inspect check details, and open PR status labels directly on GitHub."
            ),
            WhatsNewEntry(
                symbol: "link.badge.plus",
                titleKey: "Create Workstreams Your Way",
                bodyKey: "Choose a workstream name and Coding Agent, or start directly from a GitHub issue with its task already loaded."
            ),
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
                symbol: "rectangle.3.group.bubble.fill",
                titleKey: "Dockyard Overview",
                bodyKey: "See workstreams that need you, active Coding Agents, reviews, and ideas in one place."
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
