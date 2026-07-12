// ABOUTME: Represents the selected item in the sidebar.
// ABOUTME: Can be either a project or a workstream, enabling single-selection across both.

import Foundation
import OSLog

private let logger = Logger(subsystem: "dockyard", category: "sidebar-selection")

enum SidebarSelection: Hashable, Codable {
    case project(UUID)
    case workstream(UUID)
    case settings
    case help

    var projectID: UUID? {
        if case let .project(id) = self { return id }
        return nil
    }

    var workstreamID: UUID? {
        if case let .workstream(id) = self { return id }
        return nil
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "dockyard.selection"

    static func loadSaved() -> SidebarSelection? {
        let defaults = DemoMode.isEnabled ? DemoMode.defaults : UserDefaults.standard
        guard let data = defaults.data(forKey: userDefaultsKey),
              let selection = try? JSONDecoder().decode(SidebarSelection.self, from: data)
        else { return nil }
        return selection
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let defaults = DemoMode.isEnabled ? DemoMode.defaults : UserDefaults.standard
        defaults.set(data, forKey: Self.userDefaultsKey)
    }
}

enum SidebarState {
    private static let userDefaultsKey = "dockyard.expandedProjects"

    static func loadExpanded() -> Set<UUID> {
        if DemoMode.isEnabled { return [DemoMode.projectID] }
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data)
        else { return [] }
        return ids
    }

    static func saveExpanded(_ ids: Set<UUID>) {
        if DemoMode.isEnabled { return }
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

enum SidebarMode: String, CaseIterable {
    case expanded
    case collapsed
    case hidden

    static let storageKey = "dockyard.sidebarMode"
    static let lastVisibleStorageKey = "dockyard.sidebarLastVisibleMode"

    var isVisible: Bool {
        self != .hidden
    }

    static func load(defaults: UserDefaults = .standard) -> SidebarMode {
        SidebarMode(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .expanded
    }

    static func loadLastVisible(defaults: UserDefaults = .standard) -> SidebarMode {
        let mode = SidebarMode(rawValue: defaults.string(forKey: lastVisibleStorageKey) ?? "") ?? .expanded
        return mode.isVisible ? mode : .expanded
    }

    static func save(_ mode: SidebarMode, defaults: UserDefaults = .standard) {
        if mode.isVisible {
            defaults.set(mode.rawValue, forKey: lastVisibleStorageKey)
        }
        defaults.set(mode.rawValue, forKey: storageKey)
    }

    static func saveLastVisible(_ mode: SidebarMode, defaults: UserDefaults = .standard) {
        guard mode.isVisible else { return }
        defaults.set(mode.rawValue, forKey: lastVisibleStorageKey)
    }
}
