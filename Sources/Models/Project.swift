// ABOUTME: Data models for projects and workstreams.
// ABOUTME: Each project has a directory and multiple workstreams, each with its own terminal.

import Foundation

enum WorkstreamStage: String, Codable, CaseIterable {
    case auto
    case working
    case review
    case done

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = WorkstreamStage(rawValue: rawValue) ?? .auto
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func displayStage(prState: String?) -> WorkstreamDisplayStage {
        switch self {
        case .working:
            return .normal
        case .review:
            return .review
        case .done:
            return .done
        case .auto:
            if prState == "MERGED" { return .done }
            if prState == "OPEN" { return .review }
            return .normal
        }
    }
}

enum WorkstreamDisplayStage: Equatable {
    case normal
    case review
    case done
}

struct Workstream: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var worktreePath: String?
    var bypassPermissions: Bool
    var lastAccessedAt: Date
    var stage: WorkstreamStage

    init(name: String, worktreePath: String? = nil, bypassPermissions: Bool = false, id: UUID = UUID(), lastAccessedAt: Date = Date(), stage: WorkstreamStage = .auto) {
        self.id = id
        self.name = name
        self.worktreePath = worktreePath
        self.bypassPermissions = bypassPermissions
        self.lastAccessedAt = lastAccessedAt
        self.stage = stage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case worktreePath
        case bypassPermissions
        case lastAccessedAt
        case stage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        bypassPermissions = try container.decode(Bool.self, forKey: .bypassPermissions)
        lastAccessedAt = try container.decode(Date.self, forKey: .lastAccessedAt)
        stage = try container.decodeIfPresent(WorkstreamStage.self, forKey: .stage) ?? .auto
    }

    var isStageManuallySet: Bool {
        stage != .auto
    }

    func displayStage(prState: String?) -> WorkstreamDisplayStage {
        stage.displayStage(prState: prState)
    }

    /// The working directory for this workstream's terminals.
    /// Uses the worktree path if available, otherwise falls back to the project directory.
    func workingDirectory(projectDirectory: String) -> String {
        worktreePath ?? projectDirectory
    }

    static func == (lhs: Workstream, rhs: Workstream) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var directory: String
    var workstreams: [Workstream]
    var lastAccessedAt: Date

    init(name: String, directory: String, id: UUID = UUID(), workstreams: [Workstream] = [], lastAccessedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.directory = directory
        self.workstreams = workstreams
        self.lastAccessedAt = lastAccessedAt
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ProjectSortOrder: String, CaseIterable {
    case recent = "Recent"
    case alphabetical = "A-Z"
}
