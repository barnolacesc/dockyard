// ABOUTME: Data model for guided tour flows: anchor IDs, steps, and advance rules.
// ABOUTME: Flows are static content; TourController owns runtime state.

import Foundation

extension Notification.Name {
    /// Posted after .dockyard.json is written (generate sheet or manual editor).
    static let configGenerated = Notification.Name("dockyard.configGenerated")
    /// Posted when a run script actually starts executing.
    static let runScriptStarted = Notification.Name("dockyard.runScriptStarted")
    /// Posted to start the Getting Started tour (Help menu, onboarding button).
    static let startTour = Notification.Name("dockyard.startTour")
    /// Posted to open the What's New sheet manually (Help menu).
    static let openWhatsNew = Notification.Name("dockyard.openWhatsNew")
}

/// Stable identifiers for controls the tour can point at.
enum TourAnchorID: String, CaseIterable {
    case newProjectButton
    case newWorkstreamButton
    case workspaceTabBar
    case agentPicker
    case agentTab
    case infoTab
    case generateConfigButton
    case startRunButton
}

/// How a step advances to the next one.
enum TourAdvance {
    /// User clicks Next on the card.
    case manual
    /// Auto-advance when this notification is posted (Skip always available).
    case notification(Notification.Name)
}

struct TourStep {
    let id: String
    /// nil = centered card without spotlight.
    let anchor: TourAnchorID?
    /// Localization keys (literal English strings, existing convention).
    let titleKey: String
    let bodyKey: String
    let advance: TourAdvance
    /// Runs when the step becomes active (e.g. navigate to the Info tab).
    /// The `= nil` default is required: call sites omit it via the memberwise init.
    var onEnter: (() -> Void)? = nil
}

struct TourFlow {
    let id: String
    let steps: [TourStep]
}
