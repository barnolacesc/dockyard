// ABOUTME: Isolated, deterministic fixtures used only by the website capture workflow.
// ABOUTME: Demo mode is opt-in and never reads or writes a normal Dockyard project list.

import AppKit
import Foundation

enum DemoMode {
    static let argument = "--demo-mode"
    static let autoplayArgument = "--demo-autoplay"
    static let projectID = UUID(uuidString: "D0C00000-0000-4000-8000-000000000001")!
    static let checkInodeID = UUID(uuidString: "D0C00000-0000-4000-8000-000000000101")!
    static let sidebarPolishID = UUID(uuidString: "D0C00000-0000-4000-8000-000000000102")!
    static let releaseNotesID = UUID(uuidString: "D0C00000-0000-4000-8000-000000000103")!
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: "com.barnolacesc.dockyard.website-demo")!

    static var isEnabled: Bool {
        CommandLine.arguments.contains(argument)
            || ProcessInfo.processInfo.environment["DOCKYARD_DEMO_MODE"] == "1"
    }

    static var shouldAutoplay: Bool {
        CommandLine.arguments.contains(autoplayArgument)
            || ProcessInfo.processInfo.environment["DOCKYARD_DEMO_AUTOPLAY"] == "1"
    }

    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["DOCKYARD_DEMO_ROOT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("dockyard-website-demo", isDirectory: true)
    }

    static func bootstrap() {
        guard isEnabled else { return }
        if let readyFile = ProcessInfo.processInfo.environment["DOCKYARD_DEMO_READY_FILE"] {
            try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(
                toFile: readyFile, atomically: true, encoding: .utf8
            )
        }
        defaults.removePersistentDomain(forName: "com.barnolacesc.dockyard.website-demo")
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        let names = ["check-short-inode", "sidebar-polish", "release-notes"]
        for name in names {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: directory.appendingPathComponent("Sources/Models"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: directory.appendingPathComponent("Tests"), withIntermediateDirectories: true)
            try? fixtureSource.write(to: directory.appendingPathComponent("Sources/Models/InodeDetector.swift"), atomically: true, encoding: .utf8)
            try? fixtureTest.write(to: directory.appendingPathComponent("Tests/InodeDetectorTests.swift"), atomically: true, encoding: .utf8)
            try? demoPage.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            try? "{\n  \"run\": \"python3 -m http.server 4317 --bind 127.0.0.1\",\n  \"port\": 4317\n}\n".write(
                to: directory.appendingPathComponent(".dockyard.json"), atomically: true, encoding: .utf8
            )
        }

        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let project = Project(name: "Dockyard", directory: root.path, id: projectID, workstreams: [
            Workstream(name: "check-short-inode", worktreePath: root.appendingPathComponent("check-short-inode").path, id: checkInodeID, lastAccessedAt: now),
            Workstream(name: "sidebar-polish", worktreePath: root.appendingPathComponent("sidebar-polish").path, id: sidebarPolishID, lastAccessedAt: now.addingTimeInterval(-60), stage: .review),
            Workstream(name: "release-notes", worktreePath: root.appendingPathComponent("release-notes").path, id: releaseNotesID, lastAccessedAt: now.addingTimeInterval(-120), stage: .done),
        ], lastAccessedAt: now)

        ProjectStore.save([project])
        defaults.set(true, forKey: SidebarManualOrderMigration.seededKey)
    }

    @MainActor static func prepareWindow() {
        guard isEnabled else { return }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        window.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 800), display: true)
        window.title = "Dockyard"
    }

    static func cleanup() {
        guard isEnabled else { return }
        try? FileManager.default.removeItem(at: root)
    }

    static func branch(for path: String?) -> String? {
        guard isEnabled, let path else { return nil }
        return "dy/" + URL(fileURLWithPath: path).lastPathComponent
    }

    static func task(for path: String?) -> String? {
        guard isEnabled, let path else { return nil }
        switch URL(fileURLWithPath: path).lastPathComponent {
        case "check-short-inode": return "Fix short inode detection"
        case "sidebar-polish": return "Polish workstream status rows"
        case "release-notes": return "Prepare release notes"
        default: return nil
        }
    }

    static func worktreeState(for path: String) -> WorktreeState? {
        guard isEnabled else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return WorktreeState(
            hasUncommittedChanges: name == "check-short-inode",
            hasUnpushedCommits: name != "release-notes",
            hasBranchCommits: true,
            hasRemote: true,
            commitsAhead: name == "check-short-inode" ? 2 : 1,
            uncommittedCount: name == "check-short-inode" ? 1 : 0,
            branchCreatedDate: Date(timeIntervalSince1970: 1_735_603_200),
            worktreeCreatedDate: Date(timeIntervalSince1970: 1_735_603_200),
            baseBranch: "main"
        )
    }

    static func pullRequest(branch: String) -> GitHubPR? {
        guard isEnabled else { return nil }
        if branch.hasSuffix("sidebar-polish") {
            return GitHubPR(number: 184, title: "Polish workstream status rows", state: "OPEN", branch: branch, url: "https://example.invalid/dockyard/pull/184")
        }
        if branch.hasSuffix("release-notes") {
            return GitHubPR(number: 183, title: "Prepare release notes", state: "MERGED", branch: branch, url: "https://example.invalid/dockyard/pull/183")
        }
        if branch.hasSuffix("check-short-inode"), defaults.bool(forKey: "dockyard.demo.prCreated") {
            return GitHubPR(number: 185, title: "Fix short inode detection", state: "OPEN", branch: branch, url: "https://example.invalid/dockyard/pull/185")
        }
        return nil
    }

    private static let fixtureSource = """
    import Foundation

    enum InodeDetector {
        static func isShort(_ value: UInt64) -> Bool {
            value <= UInt64(UInt32.max)
        }
    }
    """

    private static let fixtureTest = """
    import XCTest
    @testable import Dockyard

    final class InodeDetectorTests: XCTestCase {
        func testDetectsShortInodeBoundary() {
            XCTAssertTrue(InodeDetector.isShort(UInt64(UInt32.max)))
            XCTAssertFalse(InodeDetector.isShort(UInt64(UInt32.max) + 1))
        }
    }
    """

    private static let demoPage = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    body{margin:0;background:#0b1020;color:#f7f8fb;font:16px -apple-system;padding:64px}main{max-width:760px;margin:auto}
    .pill{display:inline-block;color:#75d69c;background:#173629;padding:8px 12px;border-radius:999px}h1{font-size:48px;margin:28px 0 12px}p{color:#aeb7ca;font-size:20px;line-height:1.5}.card{margin-top:40px;padding:28px;background:#141c31;border-radius:20px;box-shadow:0 0 0 1px #ffffff1a}
    </style></head><body><main><span class="pill">All tests passing</span><h1>Short inode detection is fixed.</h1><p>The regression test now covers the UInt32 boundary without changing the fast path.</p><div class="card">✓ 42 tests passed &nbsp; · &nbsp; Preview running on port 4317</div></main></body></html>
    """
}

extension Notification.Name {
    static let demoAgentCreatePR = Notification.Name("dockyard.demo.agent-create-pr")
}
