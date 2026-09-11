// ABOUTME: Represents the selected item in the sidebar.
// ABOUTME: Can be either a project or a workstream, enabling single-selection across both.

import Foundation
import OSLog

private let logger = Logger(subsystem: "dockyard", category: "sidebar-selection")

enum SidebarSelection: Hashable, Codable {
    case project(UUID)
    case workstream(UUID)
    case attention
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

    static func loadSaved(defaults: UserDefaults = .standard) -> SidebarSelection? {
        SidebarPersistence.decode(SidebarSelection.self, forKey: userDefaultsKey, defaults: defaults)
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }
}

enum SidebarState {
    private static let userDefaultsKey = "dockyard.expandedProjects"

    static func loadExpanded(defaults: UserDefaults = .standard) -> Set<UUID> {
        SidebarPersistence.decode(Set<UUID>.self, forKey: userDefaultsKey, defaults: defaults) ?? []
    }

    static func saveExpanded(_ ids: Set<UUID>, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }
}

enum SidebarPersistence {
    static let maximumSnapshotBytes = 1_048_576

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String,
        defaults: UserDefaults
    ) -> Value? {
        guard let data = defaults.data(forKey: key),
              data.count <= maximumSnapshotBytes
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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
