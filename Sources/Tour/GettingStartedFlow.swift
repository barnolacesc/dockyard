// ABOUTME: Content of the Getting Started tour: project -> workstream -> agent
// ABOUTME: -> prompt -> .dockyard.json -> run. Steps 2/3/7/8 auto-advance on app events.

import Foundation

enum GettingStartedFlow {
    static let id = "getting-started"

    @MainActor
    static func make() -> TourFlow {
        TourFlow(id: id, steps: [
            TourStep(
                id: "welcome",
                anchor: nil,
                titleKey: "Welcome to Dockyard",
                bodyKey: "This short tour sets up a real project: you'll add a repository, create a workstream, and put the Coding Agent to work. You can quit anytime.",
                advance: .manual
            ),
            TourStep(
                id: "add-project",
                anchor: .newProjectButton,
                titleKey: "Add a project",
                bodyKey: "Click the highlighted + button and choose a git repository. Dockyard organizes everything around your projects.",
                advance: .notification(.projectCreated)
            ),
            TourStep(
                id: "add-workstream",
                anchor: .newWorkstreamButton,
                titleKey: "Create a workstream",
                bodyKey: "Hover over your project and click its + button. A workstream is an isolated git worktree with its own branch, terminal, and Coding Agent.",
                advance: .notification(.workstreamCreated)
            ),
            TourStep(
                id: "workspace-tabs",
                anchor: .workspaceTabBar,
                titleKey: "Your workspace",
                bodyKey: "Every workstream has an Info tab and a Coding Agent tab. Add terminals, browsers, and editors on demand — they all live here.",
                advance: .manual
            ),
            TourStep(
                id: "pick-agent",
                anchor: .agentPicker,
                titleKey: "Choose your Coding Agent",
                bodyKey: "Pick Claude Code or Codex for this workstream, or keep the default from Settings.",
                advance: .manual,
                onEnter: { NotificationCenter.default.post(name: .toggleInfo, object: nil) }
            ),
            TourStep(
                id: "prompt-agent",
                anchor: .agentTab,
                titleKey: "Prompt the agent",
                bodyKey: "Type what you want built. The agent works on this workstream's branch and never touches your main checkout.",
                advance: .manual,
                onEnter: { NotificationCenter.default.post(name: .focusAgent, object: nil) }
            ),
            TourStep(
                id: "configure-run",
                anchor: .generateConfigButton,
                titleKey: "Configure run scripts",
                bodyKey: "Generate a .dockyard.json so Dockyard knows how to set up and run your app. It detects your stack automatically.",
                advance: .notification(.configGenerated),
                onEnter: { NotificationCenter.default.post(name: .toggleInfo, object: nil) }
            ),
            TourStep(
                id: "start-run",
                anchor: .startRunButton,
                titleKey: "Start your app",
                bodyKey: "Press Start (⌘⇧↩) to run your app. When a port is detected, the embedded browser opens it automatically.",
                advance: .notification(.runScriptStarted)
            ),
            TourStep(
                id: "done",
                anchor: nil,
                titleKey: "You're all set",
                bodyKey: "Press ⌘/ anytime for help and shortcuts. You can restart this tour from the Help menu.",
                advance: .manual
            ),
        ])
    }
}
