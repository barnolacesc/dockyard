// ABOUTME: Passive showcase for opening and navigating workspace tabs.
// ABOUTME: Every step is manual so the tour never creates tabs or runs commands.

import Foundation

enum WorkspaceTabsFlow {
    static let id = "workspace-tabs"

    @MainActor
    static func make() -> TourFlow {
        TourFlow(id: id, steps: [
            TourStep(
                id: "tab-overview",
                anchor: .workspaceTabBar,
                titleKey: "Workspace tabs at a glance",
                bodyKey: "Info and Coding Agent are always ready. Extra terminals, browsers, and editors stay grouped with this workstream.",
                advance: .manual
            ),
            TourStep(
                id: "open-tools",
                anchor: .workspaceTabBar,
                titleKey: "Open the tool you need",
                bodyKey: "Press ⌘T for a terminal, ⌘B for a browser, or ⌘O for an editor. This tour never opens them for you.",
                advance: .manual
            ),
            TourStep(
                id: "switch-tabs",
                anchor: .workspaceTabBar,
                titleKey: "Move between tabs",
                bodyKey: "Press ⌘3–9 to jump directly, or ⌘⇧[ and ⌘⇧] to cycle through every open tab.",
                advance: .manual
            ),
            TourStep(
                id: "done",
                anchor: nil,
                titleKey: "Keep working your way",
                bodyKey: "The tour is complete. Press ⌘/ whenever you want the full keyboard shortcut reference.",
                advance: .manual
            ),
        ])
    }
}

enum TourFlowCatalog {
    @MainActor
    static func make(flowID: String) -> TourFlow? {
        switch flowID {
        case GettingStartedFlow.id:
            GettingStartedFlow.make()
        case WorkspaceTabsFlow.id:
            WorkspaceTabsFlow.make()
        default:
            nil
        }
    }
}
