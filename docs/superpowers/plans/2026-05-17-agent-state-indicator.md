# Reliable Agent State Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unreliable terminal-title and BEL-based sidebar indicator with an authoritative agent-lifecycle signal sourced from Claude Code hooks via per-workstream JSON state files.

**Architecture:** A bundled `dy-agent-state` helper binary writes JSON to `~/Library/Caches/dockyard/agent-state/<wsID>.json` when invoked by Claude Code hooks (`UserPromptSubmit` → working, `Notification` → waiting, `Stop` → idle). Dockyard generates a per-workstream `claude-settings.json` at agent launch and passes it via `--settings`. An `AgentStateStore` singleton watches the agent-state directory with kqueue (mirroring `PortDetector`) and publishes `[UUID: AgentState]` to SwiftUI.

**Tech Stack:** Swift 6 / SwiftUI / AppKit (macOS 14+), XcodeGen, XCTest, `DispatchSource.makeFileSystemObjectSource` for filesystem watching, Foundation `JSONEncoder`/`JSONDecoder`.

**Spec:** `docs/superpowers/specs/2026-05-17-agent-state-indicator-design.md`

**Three PRs:**
1. PR 1 (Tasks 1–9) — Helper, store, settings writer, hook wiring. No UI change.
2. PR 2 (Tasks 10–15) — Indicator cutover; remove old bell/title/focus-clear plumbing.
3. PR 3 (Tasks 16–18) — Delete `WorkstreamActivityTracker` and dead notification names.

---

## File Structure

**New files:**

- `Sources/Models/AgentState.swift` — `AgentState` enum + `AgentStateSnapshot` Codable + `AgentStateStore` static URL helpers.
- `Sources/Models/AgentStateStore.swift` — Singleton `ObservableObject`. Watches the directory with kqueue, parses each file into `[UUID: AgentState]`, publishes the map.
- `Sources/Models/AgentHooks.swift` — Generates the per-workstream `claude-settings.json`. Owns `agentHookSettings(for cli: CodingCLI) -> URL?`.
- `Sources/AgentStateHelper/main.swift` — `dy-agent-state` executable; parses CLI args, writes one state file, exits.
- `Tests/AgentStateTests.swift` — Tests `AgentState` serialization, `AgentStateSnapshot` Codable round-trips, stale-pid detection.
- `Tests/AgentHooksTests.swift` — Tests `claude-settings.json` generation and `agentHookSettings(for:)` per-CLI matrix.

**Modified files (PR 1):**

- `project.yml` — Add `DyAgentState` tool target; add post-build script in `Dockyard` target to bundle the helper at `Contents/Helpers/dy-agent-state`.
- `Sources/Models/CommandBuilder.swift:383-446` — `buildClaudeAgentCommand` gains a `settingsPath: URL?` parameter; emits `--settings <path>` when non-nil.
- `Sources/Models/CommandBuilder.swift:275-334` — `buildAgentCommand` gains a `settingsPath: URL?` parameter forwarded into `buildClaudeAgentCommand`.
- `Sources/Views/TerminalContainerView.swift:412-446` — `buildAgentCommand()` calls `AgentHooks.writeSettings(for:cli:)` for the workstream and passes the resulting URL to `CodingCLICommandBuilder.buildAgentCommand`.

**Modified files (PR 2):**

- `Sources/Views/ProjectSidebar.swift:165-180` — `WorkstreamRow` constructor takes `agentState: AgentState` instead of `isActive: Bool` / `needsAttention: Bool`.
- `Sources/Views/ProjectSidebar.swift:189` — auto-scroll predicate uses `agentState == .waiting`.
- `Sources/Views/ProjectSidebar.swift:880-1056` — `WorkstreamRow.body` and `ActivityIndicator` updated to use `AgentState`. Accent color overrides on headline (line 932) and subtitle (line 951) use `agentState == .waiting`.
- `Sources/Views/ProjectSidebar.swift` (sidebar root) — inject `AgentStateStore.shared` via `@StateObject` or read from `@EnvironmentObject`.
- `Sources/Terminal/TerminalApp.swift:81-86` — Remove the post of `.terminalNeedsAttention` from the `GHOSTTY_ACTION_RING_BELL` branch (the desktop notification stays).
- `Sources/Terminal/TerminalView.swift:172, 356, 649` — Remove all three `.terminalClearAttention` posts.
- `Sources/Models/WorkstreamArchiver.swift:25-28, 80-83` — Delete `~/Library/Caches/dockyard/agent-state/<wsID>.json` and `~/Library/Caches/dockyard/claude-settings/<wsID>.json` alongside the existing `SetupStateStore.remove`.

**Deleted files (PR 3):**

- `Sources/Models/WorkstreamActivityTracker.swift` — Entire file once all call sites are gone.
- `Tests/WorkstreamActivityTrackerTests.swift` — Companion test file.
- `Sources/Terminal/TerminalView.swift:12-13` — Notification name declarations for `terminalNeedsAttention` and `terminalClearAttention`.

---

## PR 1 — Helper, store, settings writer, hook wiring

### Task 1: `AgentState` enum and `AgentStateSnapshot` Codable

**Files:**
- Create: `Sources/Models/AgentState.swift`
- Test: `Tests/AgentStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStateTests.swift`:

```swift
// ABOUTME: Tests for AgentState enum and AgentStateSnapshot Codable round-trip.

@testable import Dockyard
import XCTest

final class AgentStateTests: XCTestCase {
    func testAgentStateRawValues() {
        XCTAssertEqual(AgentState.working.rawValue, "working")
        XCTAssertEqual(AgentState.waiting.rawValue, "waiting")
        XCTAssertEqual(AgentState.idle.rawValue, "idle")
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = AgentStateSnapshot(
            state: .working,
            updatedAt: Date(timeIntervalSince1970: 1_715_961_131),
            pid: 48211
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentStateSnapshot.self, from: data)

        XCTAssertEqual(decoded.state, .working)
        XCTAssertEqual(decoded.pid, 48211)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, 1_715_961_131, accuracy: 0.001)
    }

    func testFileURLContainsLowercaseUUID() {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let url = AgentStateFiles.fileURL(for: id)
        XCTAssertTrue(url.path.hasSuffix("agent-state/aabbccdd-1122-3344-5566-778899aabbcc.json"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/dev.sh test`
Expected: FAIL with "Cannot find 'AgentState'" or "Cannot find 'AgentStateSnapshot'".

- [ ] **Step 3: Create the source file**

Create `Sources/Models/AgentState.swift`:

```swift
// ABOUTME: Agent lifecycle state model and on-disk snapshot format.
// ABOUTME: Written by the dy-agent-state helper, read by AgentStateStore.

import Foundation

/// The lifecycle state of a workstream's Coding Agent.
enum AgentState: String, Codable, Equatable {
    /// Agent is processing a turn (most recent hook was UserPromptSubmit).
    case working
    /// Agent is blocked waiting for the user (most recent hook was Notification).
    case waiting
    /// Agent's turn ended (most recent hook was Stop) or process is dead.
    case idle
}

/// On-disk snapshot written by `dy-agent-state` and read by `AgentStateStore`.
struct AgentStateSnapshot: Codable, Equatable {
    let state: AgentState
    let updatedAt: Date
    let pid: Int32
}

/// Static helpers for the on-disk state files. The observable singleton that
/// watches the directory and publishes changes is `AgentStateStore` (added in
/// the next task).
enum AgentStateFiles {
    static var directoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("agent-state", isDirectory: true)
    }

    static func fileURL(for workstreamID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    static func load(for workstreamID: UUID) -> AgentStateSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: workstreamID)) else { return nil }
        return try? decoder.decode(AgentStateSnapshot.self, from: data)
    }

    /// Returns the snapshot only if the recorded pid is still alive. Stale files
    /// are returned as nil (the indicator shows `unknown`, i.e. no dot).
    static func loadValidated(for workstreamID: UUID) -> AgentStateSnapshot? {
        guard let snapshot = load(for: workstreamID),
              RunStateStore.isProcessRunning(pid: snapshot.pid)
        else {
            return nil
        }
        return snapshot
    }

    static func write(_ snapshot: AgentStateSnapshot, for workstreamID: UUID) throws {
        let data = try encoder.encode(snapshot)
        try FilePersistence.writeAtomically(data, to: fileURL(for: workstreamID))
    }

    static func remove(for workstreamID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: workstreamID))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

Note: `RunStateStore.isProcessRunning(pid:)` is a static helper already defined in `Sources/Models/RunState.swift`. `FilePersistence.writeAtomically` already exists in `Sources/Models/FilePersistence.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/dev.sh test`
Expected: PASS — all three `AgentStateTests` succeed.

- [ ] **Step 5: Regenerate Xcode project**

The new `Sources/Models/AgentState.swift` and `Tests/AgentStateTests.swift` must be added to the xcodeproj.

Run: `xcodegen generate`
Expected: "Generated project successfully" (or similar). The new file is now compiled.

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/AgentState.swift Tests/AgentStateTests.swift Dockyard.xcodeproj
git commit -m "feat(models): add AgentState enum and snapshot store"
```

---

### Task 2: `AgentStateStore` singleton — kqueue-backed observable

**Files:**
- Create: `Sources/Models/AgentStateStore.swift`
- Reference: `Sources/Models/PortDetector.swift` (template for the kqueue pattern)

This task adds the *observable* singleton that watches the directory. The static helpers `AgentStateFiles` from Task 1 are reused; `AgentStateStore` is a different class with the observable behavior.

- [ ] **Step 1: Write the failing test for the observable store**

Append to `Tests/AgentStateTests.swift`:

```swift
@MainActor
final class AgentStateStoreTests: XCTestCase {
    private func writeSnapshot(_ state: AgentState, pid: Int32, for id: UUID) throws {
        try FileManager.default.createDirectory(at: AgentStateFiles.directoryURL, withIntermediateDirectories: true)
        let snapshot = AgentStateSnapshot(state: state, updatedAt: Date(), pid: pid)
        try AgentStateFiles.write(snapshot, for: id)
    }

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: AgentStateFiles.directoryURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: AgentStateFiles.directoryURL)
        super.tearDown()
    }

    func testInitialScanLoadsExistingFiles() throws {
        let id = UUID()
        try writeSnapshot(.working, pid: Int32(getpid()), for: id)

        let store = AgentStateStore()
        store.refresh()

        XCTAssertEqual(store.agentState(for: id), .working)
    }

    func testReturnsUnknownForStalePid() throws {
        let id = UUID()
        // pid 1 is launchd; always alive. Use a clearly dead pid instead.
        try writeSnapshot(.working, pid: Int32(99999), for: id)

        let store = AgentStateStore()
        store.refresh()

        XCTAssertNil(store.agentState(for: id))
    }

    func testReturnsNilForUnknownID() {
        let store = AgentStateStore()
        XCTAssertNil(store.agentState(for: UUID()))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/dev.sh test`
Expected: FAIL with "Cannot find 'AgentStateStore'".

- [ ] **Step 3: Create the observable store**

Create `Sources/Models/AgentStateStore.swift`:

```swift
// ABOUTME: Observable singleton that watches ~/Library/Caches/dockyard/agent-state/
// ABOUTME: with kqueue. Mirrors the pattern used by PortDetector for run-state files.

import Foundation

@MainActor
final class AgentStateStore: ObservableObject {
    static let shared = AgentStateStore()

    @Published private(set) var states: [UUID: AgentState] = [:]

    private let queue = DispatchQueue(label: "dockyard.agent-state-store")
    private var directorySource: DispatchSourceFileSystemObject?

    init() {
        start()
    }

    deinit {
        directorySource?.cancel()
    }

    func agentState(for workstreamID: UUID) -> AgentState? {
        states[workstreamID]
    }

    /// Synchronous rescan of the directory. Tests call this directly so they
    /// do not depend on filesystem-event delivery timing.
    func refresh() {
        let next = Self.scanDirectory()
        DispatchQueue.main.async { [weak self] in
            self?.states = next
        }
    }

    private func start() {
        try? FileManager.default.createDirectory(at: AgentStateFiles.directoryURL, withIntermediateDirectories: true)
        attachDirectoryWatcher()
        refresh()
    }

    private func attachDirectoryWatcher() {
        let path = AgentStateFiles.directoryURL.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        directorySource = source
        source.resume()
    }

    private static func scanDirectory() -> [UUID: AgentState] {
        let dir = AgentStateFiles.directoryURL
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [UUID: AgentState] = [:]
        for url in entries where url.pathExtension == "json" {
            let basename = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: basename) else { continue }
            guard let snapshot = AgentStateFiles.loadValidated(for: id) else { continue }
            result[id] = snapshot.state
        }
        return result
    }
}
```

The `refresh()` method assigns on the main queue so that tests calling `store.refresh()` immediately followed by a read pick up the new value synchronously when the test is also `@MainActor` (the dispatch_async to main lands before the test's next runloop turn). If a test flakes, add `RunLoop.main.run(until: Date().addingTimeInterval(0.05))` before the assertion — see `WorkstreamActivityTrackerTests` for precedent.

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/dev.sh test`
Expected: PASS — `AgentStateStoreTests` succeed.

If `testInitialScanLoadsExistingFiles` is flaky because of the main-queue hop, change the test to call:

```swift
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
```

before the assertion.

- [ ] **Step 5: Regenerate Xcode project**

Run: `xcodegen generate`

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/AgentState.swift Sources/Models/AgentStateStore.swift Tests/AgentStateTests.swift Dockyard.xcodeproj
git commit -m "feat(models): add AgentStateStore observable for agent-state files"
```

---

### Task 3: `dy-agent-state` helper executable

**Files:**
- Create: `Sources/AgentStateHelper/main.swift`
- Modify: `project.yml` (new `DyAgentState` target + post-build bundling step)

The helper is a tool-type target like `FFRun` (the `dy-run` helper). It shares source files via xcodegen's `sources:` block. It does not get its own test target — same pattern as `dy-run`. Its logic is exercised end-to-end through manual testing (Task 9).

- [ ] **Step 1: Create the helper source**

Create `Sources/AgentStateHelper/main.swift`:

```swift
// ABOUTME: dy-agent-state helper. Invoked by Claude Code hooks to write a one-line
// ABOUTME: JSON state file at ~/Library/Caches/dockyard/agent-state/<wsID>.json.

import Darwin
import Foundation

let arguments = CommandLine.arguments

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: dy-agent-state --workstream-id <uuid> --state <working|waiting|idle>\n".utf8))
    exit(2)
}

func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

guard let idString = value(for: "--workstream-id"),
      let id = UUID(uuidString: idString),
      let stateString = value(for: "--state"),
      let state = AgentState(rawValue: stateString)
else {
    usage()
}

// Record the parent's pid (the `claude` process that invoked us as a hook)
// rather than our own — the helper exits immediately, but the agent process
// stays alive. The store's loadValidated() uses this for liveness checks.
let agentPID = getppid()
let snapshot = AgentStateSnapshot(state: state, updatedAt: Date(), pid: agentPID)

do {
    try FileManager.default.createDirectory(at: AgentStateFiles.directoryURL, withIntermediateDirectories: true)
    try AgentStateFiles.write(snapshot, for: id)
    exit(0)
} catch {
    FileHandle.standardError.write(Data("dy-agent-state: write failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
```

- [ ] **Step 2: Add the helper target to `project.yml`**

Open `project.yml`. Find the `FFRun` target (around line 179). Add a new sibling target immediately after it:

```yaml
  DyAgentState:
    type: tool
    platform: macOS
    sources:
      - path: Sources/AgentStateHelper
      - path: Sources/Models/AgentConstants.swift
        optional: true
      - path: Sources/Models/AgentState.swift
      - path: Sources/Models/AppConstants.swift
      - path: Sources/Models/AppCommit.swift
      - path: Sources/Models/FilePersistence.swift
      - path: Sources/Models/RunState.swift
    settings:
      base:
        PRODUCT_NAME: dy-agent-state
```

Notes:
- The `AgentConstants.swift` line with `optional: true` is intentional and harmless — it can be removed if you find the YAML parser complains. It's there as a placeholder for a future split if needed.
- `AgentState.swift` references `RunStateStore.isProcessRunning(pid:)` from `RunState.swift`, and `AppConstants.cacheDirectory`. Both are listed above.
- `FilePersistence.swift` provides `writeAtomically`.

If `RunState.swift` pulls in dependencies that the helper does not need (e.g. unrelated globals), this will surface at link time — that's the moment to split shared code into a smaller file.

- [ ] **Step 3: Add the bundling step**

In `project.yml`, find the `Dockyard` target's `postBuildScripts:` (around line 168, currently bundles `dy-run`). Replace the entire `postBuildScripts:` block with:

```yaml
    postBuildScripts:
      - script: |
          set -e
          mkdir -p "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
          cp -f "${BUILT_PRODUCTS_DIR}/dy-run" "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/dy-run"
          chmod +x "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/dy-run"
          codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp --options=runtime --generate-entitlement-der "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/dy-run"
        name: Bundle dy-run
        outputFiles:
          - $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/dy-run
      - script: |
          set -e
          mkdir -p "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
          cp -f "${BUILT_PRODUCTS_DIR}/dy-agent-state" "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/dy-agent-state"
          chmod +x "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/dy-agent-state"
          codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp --options=runtime --generate-entitlement-der "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/dy-agent-state"
        name: Bundle dy-agent-state
        outputFiles:
          - $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/dy-agent-state
```

- [ ] **Step 4: Make Dockyard depend on the new helper target**

Find the `Dockyard:` target's `dependencies:` block. If it does not have one, add one. If it already has dependencies, append. Add:

```yaml
    dependencies:
      - target: FFRun
      - target: DyAgentState
```

Look for an existing `dependencies:` under `Dockyard:` first. If `FFRun` is already listed, just add `- target: DyAgentState`. If neither is listed (which would mean `dy-run` is currently being built incidentally by the post-build script), add both.

- [ ] **Step 5: Regenerate and build**

Run: `xcodegen generate && ./scripts/dev.sh build`
Expected: build succeeds. The `dy-agent-state` binary appears at `Dockyard.app/Contents/Helpers/dy-agent-state`.

- [ ] **Step 6: Verify the helper runs**

Run:

```bash
TEST_ID=$(uuidgen | tr 'A-Z' 'a-z')
./build/Build/Products/Debug/Dockyard\ Debug.app/Contents/Helpers/dy-agent-state \
  --workstream-id "$TEST_ID" --state working
cat ~/Library/Caches/dockyard-debug/agent-state/"$TEST_ID".json
```

Expected: a pretty-printed JSON file containing `"state" : "working"`, an `updatedAt` ISO-8601 timestamp, and a `pid` (the shell's pid, since the shell invoked the helper).

If the build path differs from the example above, locate the built app with:

```bash
find ./build -name "dy-agent-state" -type f
```

Clean up the test file:

```bash
rm ~/Library/Caches/dockyard-debug/agent-state/"$TEST_ID".json
```

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStateHelper/main.swift project.yml Dockyard.xcodeproj
git commit -m "feat(helper): add dy-agent-state binary for Claude Code hooks"
```

---

### Task 4: `AgentHooks` — per-workstream `claude-settings.json` writer

**Files:**
- Create: `Sources/Models/AgentHooks.swift`
- Test: `Tests/AgentHooksTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentHooksTests.swift`:

```swift
// ABOUTME: Tests AgentHooks settings.json generation and per-CLI capability matrix.

@testable import Dockyard
import XCTest

final class AgentHooksTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: AgentHooks.settingsDirectoryURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: AgentHooks.settingsDirectoryURL)
        super.tearDown()
    }

    func testHookSettingsReturnsNilForCodex() {
        XCTAssertNil(AgentHooks.settingsPathIfSupported(for: .codex))
    }

    func testHookSettingsReturnsNilForOpencode() {
        XCTAssertNil(AgentHooks.settingsPathIfSupported(for: .opencode))
    }

    func testHookSettingsReturnsNilForGemini() {
        XCTAssertNil(AgentHooks.settingsPathIfSupported(for: .gemini))
    }

    func testHookSettingsReturnsURLForClaude() {
        let id = UUID()
        let url = AgentHooks.settingsPathIfSupported(for: .claude, workstreamID: id)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.hasSuffix("claude-settings/\(id.uuidString.lowercased()).json"))
    }

    func testWriteSettingsProducesValidJSONWithThreeHooks() throws {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"
        let url = try AgentHooks.writeClaudeSettings(workstreamID: id, helperPath: helperPath)

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["UserPromptSubmit"])
        XCTAssertNotNil(hooks?["Notification"])
        XCTAssertNotNil(hooks?["Stop"])

        // Verify the helper path and UUID are embedded in the UserPromptSubmit command.
        let userPrompt = (hooks?["UserPromptSubmit"] as? [[String: Any]])?.first
        let inner = (userPrompt?["hooks"] as? [[String: Any]])?.first
        let command = inner?["command"] as? String
        XCTAssertNotNil(command)
        XCTAssertTrue(command!.contains(helperPath))
        XCTAssertTrue(command!.contains("aabbccdd-1122-3344-5566-778899aabbcc"))
        XCTAssertTrue(command!.contains("--state working"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/dev.sh test`
Expected: FAIL with "Cannot find 'AgentHooks'".

- [ ] **Step 3: Create the source file**

Create `Sources/Models/AgentHooks.swift`:

```swift
// ABOUTME: Generates per-workstream claude-settings.json files that wire
// ABOUTME: Claude Code's hooks to the bundled dy-agent-state helper.

import Foundation

enum AgentHooks {
    static var settingsDirectoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("claude-settings", isDirectory: true)
    }

    static func settingsURL(for workstreamID: UUID) -> URL {
        settingsDirectoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    /// Returns the path Claude Code's `--settings` flag should use for the given
    /// CLI, or nil if the CLI does not support hooks in a way we can target.
    static func settingsPathIfSupported(for cli: CodingCLI, workstreamID: UUID = UUID()) -> URL? {
        switch cli {
        case .claude:
            return settingsURL(for: workstreamID)
        case .codex, .opencode, .gemini:
            return nil
        }
    }

    /// Writes a fresh `claude-settings.json` for the workstream, embedding the
    /// bundled helper's absolute path and the workstream UUID. Returns the file URL.
    @discardableResult
    static func writeClaudeSettings(workstreamID: UUID, helperPath: String) throws -> URL {
        let id = workstreamID.uuidString.lowercased()
        let settings: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(helperPath) --workstream-id \(id) --state working",
                    ]],
                ]],
                "Notification": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(helperPath) --workstream-id \(id) --state waiting",
                    ]],
                ]],
                "Stop": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(helperPath) --workstream-id \(id) --state idle",
                    ]],
                ]],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: settingsDirectoryURL, withIntermediateDirectories: true)
        let url = settingsURL(for: workstreamID)
        try FilePersistence.writeAtomically(data, to: url)
        return url
    }

    /// Path to the bundled helper inside the running app. Returns nil if the
    /// helper is missing (e.g. running unbundled tests).
    static var bundledHelperPath: String? {
        guard let resourceURL = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() else {
            return nil
        }
        let candidate = resourceURL.appendingPathComponent("Helpers/dy-agent-state").path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/dev.sh test`
Expected: PASS — all `AgentHooksTests` succeed.

- [ ] **Step 5: Regenerate Xcode project**

Run: `xcodegen generate`

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/AgentHooks.swift Tests/AgentHooksTests.swift Dockyard.xcodeproj
git commit -m "feat(hooks): generate per-workstream claude-settings.json"
```

---

### Task 5: Plumb `settingsPath` through `CodingCLICommandBuilder`

**Files:**
- Modify: `Sources/Models/CommandBuilder.swift:275-446`
- Modify: `Tests/CommandBuilderTests.swift`

- [ ] **Step 1: Write a failing test**

Add this test to the appropriate XCTestCase class in `Tests/CommandBuilderTests.swift` (the file already exists — pick the class that exercises `buildAgentCommand` for Claude; if you cannot find an obvious home, add a new class at the bottom of the file):

```swift
    func testBuildClaudeAgentCommandIncludesSettingsFlag() {
        let id = UUID()
        let settingsURL = URL(fileURLWithPath: "/tmp/dockyard-test/settings.json")
        let command = CodingCLICommandBuilder.buildAgentCommand(
            cli: .claude,
            cliPath: "/usr/local/bin/claude",
            workingDirectory: "/tmp/worktree",
            projectName: "demo",
            workstreamName: "ws",
            workstreamID: id,
            tmuxPath: nil,
            useTmux: false,
            bypassPermissions: false,
            allowOutsideWorktree: true,
            autoRenameBranch: false,
            envVars: [:],
            supportsSessionName: true,
            settingsPath: settingsURL
        )
        XCTAssertTrue(command.finalCommand.contains("--settings /tmp/dockyard-test/settings.json"),
                      "expected --settings flag in command, got: \(command.finalCommand)")
    }

    func testBuildClaudeAgentCommandWithoutSettingsHasNoFlag() {
        let id = UUID()
        let command = CodingCLICommandBuilder.buildAgentCommand(
            cli: .claude,
            cliPath: "/usr/local/bin/claude",
            workingDirectory: "/tmp/worktree",
            projectName: "demo",
            workstreamName: "ws",
            workstreamID: id,
            tmuxPath: nil,
            useTmux: false,
            bypassPermissions: false,
            allowOutsideWorktree: true,
            autoRenameBranch: false,
            envVars: [:],
            supportsSessionName: true,
            settingsPath: nil
        )
        XCTAssertFalse(command.finalCommand.contains("--settings"),
                       "expected no --settings flag, got: \(command.finalCommand)")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/dev.sh test`
Expected: FAIL with "Extra argument 'settingsPath' in call".

- [ ] **Step 3: Add the parameter to `buildAgentCommand`**

In `Sources/Models/CommandBuilder.swift`, modify `buildAgentCommand` (starts at line 275). Add `settingsPath: URL?` as the last parameter:

```swift
    static func buildAgentCommand(
        cli: CodingCLI,
        cliPath: String,
        workingDirectory: String,
        projectName: String,
        workstreamName: String,
        workstreamID: UUID,
        tmuxPath: String?,
        useTmux: Bool,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool,
        autoRenameBranch: Bool,
        envVars: [String: String],
        supportsSessionName: Bool,
        settingsPath: URL? = nil
    ) -> AgentLaunchCommand {
```

Forward it into `buildClaudeAgentCommand` in the same function:

```swift
        case .claude:
            command = buildClaudeAgentCommand(
                cliPath: cliPath,
                workingDirectory: workingDirectory,
                workstreamName: workstreamName,
                workstreamID: workstreamID,
                useTmux: useTmux,
                bypassPermissions: bypassPermissions,
                allowOutsideWorktree: allowOutsideWorktree,
                autoRenameBranch: autoRenameBranch,
                supportsSessionName: supportsSessionName,
                settingsPath: settingsPath
            )
```

- [ ] **Step 4: Add the parameter to `buildClaudeAgentCommand`**

Modify the private `buildClaudeAgentCommand` (starts at line 383). Add `settingsPath: URL?` as the last parameter:

```swift
    private static func buildClaudeAgentCommand(
        cliPath: String,
        workingDirectory: String,
        workstreamName: String,
        workstreamID: UUID,
        useTmux: Bool,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool,
        autoRenameBranch: Bool,
        supportsSessionName: Bool,
        settingsPath: URL?
    ) -> AgentLaunchCommand {
```

Inside the function, after the `--append-system-prompt` block but before constructing the `fresh` command, append a `--settings` flag to both the `resume` and `fresh` `CommandBuilder` instances. Replace the existing block from `var resume = CommandBuilder(cliPath)` through the end of the `fresh` builder setup with:

```swift
        var resume = CommandBuilder(cliPath)
        resume.option("--resume", sessionID)
        if supportsSessionName {
            resume.option("--name", workstreamName)
        }
        if useTmux {
            resume.flag("--teammate-mode")
            resume.arg("tmux")
        }
        if bypassPermissions {
            resume.flag("--dangerously-skip-permissions")
        }
        if let combinedSystemPrompt {
            resume.option("--append-system-prompt", combinedSystemPrompt)
        }
        if let settingsPath {
            resume.option("--settings", settingsPath.path)
        }

        var fresh = CommandBuilder(cliPath)
        fresh.option("--session-id", sessionID)
        if supportsSessionName {
            fresh.option("--name", workstreamName)
        }
        if useTmux {
            fresh.flag("--teammate-mode")
            fresh.arg("tmux")
        }
        if bypassPermissions {
            fresh.flag("--dangerously-skip-permissions")
        }
        if let combinedSystemPrompt {
            fresh.option("--append-system-prompt", combinedSystemPrompt)
        }
        if let settingsPath {
            fresh.option("--settings", settingsPath.path)
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./scripts/dev.sh test`
Expected: PASS — both new tests succeed, and all pre-existing `CommandBuilderTests` still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/CommandBuilder.swift Tests/CommandBuilderTests.swift
git commit -m "feat(commands): plumb settingsPath through Claude agent command"
```

---

### Task 6: Wire `AgentHooks` and `--settings` into `TerminalContainerView`

**Files:**
- Modify: `Sources/Views/TerminalContainerView.swift:412-446`

- [ ] **Step 1: Update `buildAgentCommand()`**

In `Sources/Views/TerminalContainerView.swift`, locate `buildAgentCommand()` at line 412. Replace it with:

```swift
    private func buildAgentCommand() -> String? {
        guard let cliPath = selectedCodingCLIPath else { return nil }

        var settingsPath: URL?
        if let helperPath = AgentHooks.bundledHelperPath,
           let candidatePath = AgentHooks.settingsPathIfSupported(for: selectedCodingCLI, workstreamID: workstreamID)
        {
            do {
                try AgentHooks.writeClaudeSettings(workstreamID: workstreamID, helperPath: helperPath)
                settingsPath = candidatePath
            } catch {
                // Falling back to no settings is acceptable; indicator stays unknown.
                settingsPath = nil
            }
        }

        let command = CodingCLICommandBuilder.buildAgentCommand(
            cli: selectedCodingCLI,
            cliPath: cliPath,
            workingDirectory: workingDirectory,
            projectName: projectName,
            workstreamName: workstreamName,
            workstreamID: workstreamID,
            tmuxPath: appEnv.toolStatus.tmux.path,
            useTmux: tmuxMode,
            bypassPermissions: bypassPermissions,
            allowOutsideWorktree: allowOutsideWorktree,
            autoRenameBranch: autoRenameBranch,
            envVars: terminalEnvVars,
            supportsSessionName: appEnv.toolStatus.supportsSessionName(for: selectedCodingCLI),
            settingsPath: settingsPath
        )
```

Leave the rest of the function (the `Telemetry.shared.track` and `return command.finalCommand` lines) unchanged. Use `git diff` to verify only the `settingsPath` setup and the new argument at the end of the call were added.

- [ ] **Step 2: Build to confirm it compiles**

Run: `./scripts/dev.sh build`
Expected: build succeeds.

- [ ] **Step 3: Run the test suite**

Run: `./scripts/dev.sh test`
Expected: all tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/TerminalContainerView.swift
git commit -m "feat(workstream): generate claude settings and pass --settings on launch"
```

---

### Task 7: End-to-end manual verification

**Files:** none.

- [ ] **Step 1: Rebuild and launch**

Run: `./scripts/dev.sh br`

- [ ] **Step 2: Open a workstream with Claude Code configured**

Open any workstream whose Coding Agent is Claude Code. Click the Agent tab.

- [ ] **Step 3: Check the settings file was written**

In another terminal:

```bash
ls -lah ~/Library/Caches/dockyard-debug/claude-settings/
```

Expected: a file named `<workstream-uuid>.json`. Pretty-print it:

```bash
cat ~/Library/Caches/dockyard-debug/claude-settings/*.json
```

Expected: JSON with three hook entries (UserPromptSubmit, Notification, Stop), each invoking `/path/to/Dockyard Debug.app/Contents/Helpers/dy-agent-state` with the correct UUID and state.

- [ ] **Step 4: Send a prompt and watch the state file**

In the Agent tab, send a short prompt (e.g. "say hi"). In the other terminal:

```bash
ls -lah ~/Library/Caches/dockyard-debug/agent-state/
cat ~/Library/Caches/dockyard-debug/agent-state/<wsID>.json
```

Expected progression:
- Right after submit: file contains `"state" : "working"`.
- When the agent finishes its turn: file contains `"state" : "idle"`.
- If Claude requests permission or pauses for input: file contains `"state" : "waiting"`.

If any state never appears, check Claude Code's hook documentation for that release — `Notification` hook may only fire on permission prompts and not on every "waiting for input" condition. This is expected and acceptable for v1; the sidebar will show idle in that case.

- [ ] **Step 5: Verify the sidebar still uses the old indicator**

The pulsing dot in the sidebar should still behave the same as before this PR (driven by title changes and BEL). PR 2 swaps it to read from `AgentStateStore`. No regression expected here.

- [ ] **Step 6: If everything looks right, open a PR for review**

```bash
git push -u origin <branch>
gh pr create --title "feat(agent): write state files via claude code hooks" \
  --body "$(cat <<'EOF'
## Summary

Land the infrastructure for the reliable agent-state indicator without changing the UI yet. The bundled `dy-agent-state` helper writes JSON to `~/Library/Caches/dockyard/agent-state/<wsID>.json` when invoked by Claude Code hooks; `AgentStateStore` watches the directory and publishes the current state per workstream. Per-workstream `claude-settings.json` files are generated on Agent launch and passed via `--settings`.

The sidebar indicator continues to use the old title/bell heuristics — PR 2 will swap it to read from `AgentStateStore`.

Spec: `docs/superpowers/specs/2026-05-17-agent-state-indicator-design.md`

## Test plan

- [ ] Open a workstream with Claude Code
- [ ] Confirm `claude-settings/<wsID>.json` is created on Agent launch
- [ ] Send a prompt; confirm `agent-state/<wsID>.json` shows `working`, then `idle` after the turn ends
- [ ] Trigger a permission prompt; confirm `waiting` appears
EOF
)"
```

---

## PR 2 — Indicator cutover

### Task 8: Inject `AgentStateStore` and update `ActivityIndicator` signature

**Files:**
- Modify: `Sources/Views/ProjectSidebar.swift:1018-1056` (ActivityIndicator)
- Modify: `Sources/Views/ProjectSidebar.swift:883-895` (WorkstreamRow properties)
- Modify: `Sources/DockyardApp.swift` (root injection — find via grep)

- [ ] **Step 1: Find where AppEnvironment is provided to the view hierarchy**

Run:

```bash
grep -nE "@StateObject|AgentStateStore|AppEnvironment.*environmentObject|environmentObject\(" Sources/DockyardApp.swift Sources/Views/ContentView.swift
```

Identify the root view that owns `AppEnvironment` (likely `DockyardApp` via `@StateObject` or `ContentView`). The new `AgentStateStore` will be injected the same way.

- [ ] **Step 2: Inject `AgentStateStore` at the root**

In the root view (likely `DockyardApp.swift`), add a `@StateObject private var agentStateStore = AgentStateStore.shared` (or `= AgentStateStore()` if the existing pattern uses fresh instances rather than singletons). Pass it down via `.environmentObject(agentStateStore)` on the same `Window`/`WindowGroup`/root view that already attaches `appEnvironment`.

Example diff to apply (adapt to the actual structure you find):

```swift
@StateObject private var agentStateStore = AgentStateStore.shared

var body: some Scene {
    Window("Dockyard", id: "main") {
        ContentView()
            .environmentObject(appEnvironment)
            .environmentObject(agentStateStore)
    }
}
```

- [ ] **Step 3: Rewrite `ActivityIndicator`**

In `Sources/Views/ProjectSidebar.swift`, replace the `ActivityIndicator` struct (lines 1018-1056) with:

```swift
struct ActivityIndicator: View {
    let state: AgentState?
    let isPathValid: Bool

    @State private var isPulsing = false

    var body: some View {
        Group {
            if !isPathValid {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.system(size: 10))
            } else if state == .waiting {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }
            } else if state == .working {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }
            } else if state == .idle {
                Circle()
                    .fill(.tertiary)
                    .frame(width: 6, height: 6)
            }
            // state == nil (unknown) draws nothing
        }
        .frame(width: 12)
    }
}
```

The 12pt-wide frame is preserved in every branch (including the empty `unknown` case) so headlines do not shift horizontally between workstreams. The orange triangle for invalid paths still wins over agent state.

- [ ] **Step 4: Update `WorkstreamRow` properties**

In `Sources/Views/ProjectSidebar.swift`, find the `WorkstreamRow` struct (around line 883). Locate the declarations (lines 888-895 area) that read:

```swift
    var isActive: Bool = false
    var isPathValid: Bool = false
    var needsAttention: Bool = false
```

Replace them with:

```swift
    var agentState: AgentState? = nil
    var isPathValid: Bool = false
```

- [ ] **Step 5: Build to surface call sites that need fixing**

Run: `./scripts/dev.sh build`
Expected: build fails with "Missing argument for parameter 'isActive'" (or similar) at the row-construction site. Continue to the next task to fix those.

---

### Task 9: Update sidebar call sites (row construction, accent overrides, auto-scroll)

**Files:**
- Modify: `Sources/Views/ProjectSidebar.swift:165-180`
- Modify: `Sources/Views/ProjectSidebar.swift:189`
- Modify: `Sources/Views/ProjectSidebar.swift:920-955` (body of WorkstreamRow)

- [ ] **Step 1: Declare `@EnvironmentObject var agentStateStore: AgentStateStore` in the sidebar**

Near the top of the SwiftUI view that constructs `WorkstreamRow` (around line 100-165 in `ProjectSidebar.swift`), find where `appEnv` is declared as `@EnvironmentObject`. Add a sibling:

```swift
    @EnvironmentObject var agentStateStore: AgentStateStore
```

- [ ] **Step 2: Update the `WorkstreamRow` construction site**

In `Sources/Views/ProjectSidebar.swift` around line 165, find the `WorkstreamRow(...)` call. Replace the `isActive`, `needsAttention`, and `hasActivePort` arguments with a single `agentState` argument. The current call has lines like:

```swift
                        WorkstreamRow(
                            ...
                            isActive: activityTracker.isActive(workstream.id),
                            needsAttention: activityTracker.needsAttention(workstream.id),
                            hasActivePort: appEnv.hasActivePort(workstream.id),
                            ...
                        )
```

Replace `isActive:` and `needsAttention:` lines with:

```swift
                            agentState: agentStateStore.agentState(for: workstream.id),
```

(Keep `hasActivePort:` — that is unrelated to the agent state work.)

- [ ] **Step 3: Update the auto-scroll predicate**

Around line 189, find the `if activityTracker.needsAttention(workstream.id) && selection != .workstream(...` block. Replace `activityTracker.needsAttention(workstream.id)` with:

```swift
            if agentStateStore.agentState(for: workstream.id) == .waiting && selection != .workstream(...
```

(Preserve the rest of the condition.)

- [ ] **Step 4: Update the accent color overrides inside `WorkstreamRow.body`**

In `WorkstreamRow.body` (around line 923), find the headline color override:

```swift
                        .foregroundStyle(needsAttention ? AnyShapeStyle(Color.accentColor) : (isPathValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
```

Replace with:

```swift
                        .foregroundStyle(agentState == .waiting ? AnyShapeStyle(Color.accentColor) : (isPathValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
```

Find the subtitle color override around line 951:

```swift
                    .foregroundStyle(needsAttention ? AnyShapeStyle(Color.accentColor.opacity(0.8)) : (prState == "MERGED" ? AnyShapeStyle(.purple) : AnyShapeStyle(.tertiary)))
```

Replace with:

```swift
                    .foregroundStyle(agentState == .waiting ? AnyShapeStyle(Color.accentColor.opacity(0.8)) : (prState == "MERGED" ? AnyShapeStyle(.purple) : AnyShapeStyle(.tertiary)))
```

- [ ] **Step 5: Update the indicator construction inside `WorkstreamRow.body`**

Around line 925, find:

```swift
            ActivityIndicator(isActive: isActive, isPathValid: isPathValid, needsAttention: needsAttention)
```

Replace with:

```swift
            ActivityIndicator(state: agentState, isPathValid: isPathValid)
```

- [ ] **Step 6: Build to verify it compiles**

Run: `./scripts/dev.sh build`
Expected: build succeeds. If it fails with "Missing environment object 'AgentStateStore'", the injection in Task 8 step 2 needs to be confirmed.

- [ ] **Step 7: Run tests**

Run: `./scripts/dev.sh test`
Expected: existing tests still pass. (Sidebar has no UI tests; failures here would be regressions in unrelated tests.)

- [ ] **Step 8: Commit**

```bash
git add Sources/Views/ProjectSidebar.swift Sources/DockyardApp.swift
git commit -m "feat(sidebar): drive ActivityIndicator from AgentStateStore"
```

---

### Task 10: Remove BEL → `.terminalNeedsAttention` post

**Files:**
- Modify: `Sources/Terminal/TerminalApp.swift:78-102`

- [ ] **Step 1: Remove the in-app notification post**

In `Sources/Terminal/TerminalApp.swift`, locate the `case GHOSTTY_ACTION_RING_BELL:` branch (around line 78). The current code posts both `.terminalNeedsAttention` (lines 81-86) and a desktop notification (lines 88-101). Delete only the `DispatchQueue.main.async { NotificationCenter.default.post(name: .terminalNeedsAttention, object: wsID) }` block, keeping the rest.

After the edit, the `case GHOSTTY_ACTION_RING_BELL:` branch starts directly with `guard let view = TerminalView.view(for: target.target.surface)`, then proceeds to look up project/workstream names and call `sendDesktopNotification`. The `wsID` local stays — it is still used by the desktop notification body.

- [ ] **Step 2: Build to verify it compiles**

Run: `./scripts/dev.sh build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Terminal/TerminalApp.swift
git commit -m "refactor(terminal): stop posting in-app attention on BEL"
```

---

### Task 11: Remove the three `.terminalClearAttention` posts

**Files:**
- Modify: `Sources/Terminal/TerminalView.swift:172, 356, 649`

- [ ] **Step 1: Remove the focus-clear in `becomeFirstResponder`**

In `Sources/Terminal/TerminalView.swift` around line 167, replace:

```swift
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
            if let workstreamID {
                NotificationCenter.default.post(name: .terminalClearAttention, object: workstreamID)
            }
        }
        return result
    }
```

with:

```swift
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }
```

- [ ] **Step 2: Remove the typing-clear in `reportActivity`**

Around line 353, replace:

```swift
    private func reportActivity() {
        guard let workstreamID else { return }
        NotificationCenter.default.post(name: .terminalClearAttention, object: workstreamID)

        guard activityDebounceWork == nil else { return }
```

with:

```swift
    private func reportActivity() {
        guard let workstreamID else { return }

        guard activityDebounceWork == nil else { return }
```

(Remove the `terminalClearAttention` post line, leave the rest of the function untouched. Note that the `workstreamID` capture is still needed by the `.terminalActivity` post a few lines later.)

- [ ] **Step 3: Remove the mouse-clear in `mouseDown`**

Around line 644, replace:

```swift
    override func mouseDown(with event: NSEvent) {
        // Claim first responder so this surface gets keyboard input
        window?.makeFirstResponder(self)
        guard let surface else { return }
        if let workstreamID {
            NotificationCenter.default.post(name: .terminalClearAttention, object: workstreamID)
        }
        let mods = Self.eventMods(event)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }
```

with:

```swift
    override func mouseDown(with event: NSEvent) {
        // Claim first responder so this surface gets keyboard input
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let mods = Self.eventMods(event)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `./scripts/dev.sh build`
Expected: build succeeds. The `terminalClearAttention` notification name declaration at the top of the file is now orphaned but still legal Swift — PR 3 deletes it.

- [ ] **Step 5: Commit**

```bash
git add Sources/Terminal/TerminalView.swift
git commit -m "refactor(terminal): stop clearing attention on focus/typing/mouse"
```

---

### Task 12: Clean up agent-state files on archive

**Files:**
- Modify: `Sources/Models/WorkstreamArchiver.swift:25-28, 80-83`

- [ ] **Step 1: Update the `remove` path**

In `Sources/Models/WorkstreamArchiver.swift`, find the `remove` function (line 10). The cleanup block currently looks like:

```swift
        surfaceCache.removeWorkstreamSurfaces(for: workstreamID)
        LaunchLogger.removeLog(for: workstreamID)
        SetupStateStore.remove(for: workstreamID)
        project.workstreams.removeAll { $0.id == workstreamID }
```

Insert two new lines after `SetupStateStore.remove(for: workstreamID)`:

```swift
        surfaceCache.removeWorkstreamSurfaces(for: workstreamID)
        LaunchLogger.removeLog(for: workstreamID)
        SetupStateStore.remove(for: workstreamID)
        AgentStateFiles.remove(for: workstreamID)
        try? FileManager.default.removeItem(at: AgentHooks.settingsURL(for: workstreamID))
        project.workstreams.removeAll { $0.id == workstreamID }
```

- [ ] **Step 2: Update the `purge` path**

In the same file, find the `purge` function (line 54). Apply the same change to its cleanup block (around line 80).

- [ ] **Step 3: Build and run tests**

Run: `./scripts/dev.sh test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Models/WorkstreamArchiver.swift
git commit -m "refactor(archiver): clean up agent-state and claude-settings files"
```

---

### Task 13: Manual verification and PR 2 ship

**Files:** none.

- [ ] **Step 1: Rebuild and launch**

Run: `./scripts/dev.sh br`

- [ ] **Step 2: Verify the new indicator behavior**

In a workstream using Claude Code:

1. Initial state, no agent running: **no dot** in sidebar (state is `unknown`, file does not exist yet).
2. Open the Agent tab and send a prompt: dot turns **pulsing green** (working).
3. Click around the workstream while the agent is still working: dot **stays green** (focus/clicks no longer clear the signal).
4. Agent finishes its turn: dot becomes **static gray** (idle).
5. Send another prompt that triggers a permission/notification prompt in Claude: dot turns **pulsing accent** (waiting).
6. Switch focus to another app, then back: dot **stays in the same state**.

In a workstream using a non-Claude CLI (Codex/OpenCode/Gemini): **no dot** appears (state is always `unknown`).

In a workstream whose worktree directory has been deleted from disk: **orange triangle** still appears.

- [ ] **Step 3: Archive a workstream and verify cleanup**

Right-click a workstream → Archive (or use the Purge action for a test workstream). In another terminal:

```bash
ls ~/Library/Caches/dockyard-debug/agent-state/<wsID>.json 2>&1
ls ~/Library/Caches/dockyard-debug/claude-settings/<wsID>.json 2>&1
```

Expected: both `ls` commands report "No such file or directory."

- [ ] **Step 4: Open the PR**

```bash
git push
gh pr create --title "feat(sidebar): drive indicator from agent state files" \
  --body "$(cat <<'EOF'
## Summary

User-visible cutover for the agent-state indicator. The pulsing dot in the sidebar now reflects the Coding Agent's real lifecycle — `working`, `waiting`, or `idle` — sourced from the state files PR #N landed.

The bell-based `needsAttention` and title-based `isActive` heuristics are removed. The aggressive attention-clearing on focus/typing/mouse is removed, so the indicator no longer lies when you glance at a workstream.

For non-Claude CLIs (Codex, OpenCode, Gemini), no dot is drawn at all — the spec's "unknown" state. The desktop notification on terminal BEL is preserved.

Spec: `docs/superpowers/specs/2026-05-17-agent-state-indicator-design.md`

## Test plan

- [ ] No dot on a workstream whose Agent tab has never been opened
- [ ] Pulsing green during an active Claude turn
- [ ] Indicator stays green even when you focus / click / type
- [ ] Pulsing accent when Claude is waiting for input
- [ ] Static gray when the turn ends
- [ ] No dot for Codex / OpenCode / Gemini workstreams
- [ ] Orange triangle still wins for invalid worktree paths
- [ ] Archive / purge removes agent-state and claude-settings files
EOF
)"
```

---

## PR 3 — Cleanup

### Task 14: Delete `WorkstreamActivityTracker` and its tests

**Files:**
- Delete: `Sources/Models/WorkstreamActivityTracker.swift`
- Delete: `Tests/WorkstreamActivityTrackerTests.swift`

- [ ] **Step 1: Verify nothing still references the tracker**

Run:

```bash
grep -rn "WorkstreamActivityTracker\|activityTracker" Sources Tests --include="*.swift"
```

Expected: no matches outside the two files about to be deleted. If matches appear, fix those call sites first (likely a sidebar leftover from PR 2).

- [ ] **Step 2: Delete the files**

```bash
git rm Sources/Models/WorkstreamActivityTracker.swift Tests/WorkstreamActivityTrackerTests.swift
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`

- [ ] **Step 4: Build and test**

Run: `./scripts/dev.sh test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Dockyard.xcodeproj
git commit -m "refactor: remove WorkstreamActivityTracker after agent-state cutover"
```

---

### Task 15: Delete orphan notification name declarations

**Files:**
- Modify: `Sources/Terminal/TerminalView.swift:12-13`

- [ ] **Step 1: Confirm both names are unused**

Run:

```bash
grep -rn "terminalNeedsAttention\|terminalClearAttention" Sources Tests --include="*.swift"
```

Expected: only matches in `Sources/Terminal/TerminalView.swift:12-13` (the declarations themselves). If anything else appears, do not delete — first fix the remaining reference.

- [ ] **Step 2: Delete the declarations**

In `Sources/Terminal/TerminalView.swift` at lines 12-13, delete:

```swift
    static let terminalNeedsAttention = Notification.Name("dockyard.terminalNeedsAttention")
    static let terminalClearAttention = Notification.Name("dockyard.terminalClearAttention")
```

- [ ] **Step 3: Build to confirm**

Run: `./scripts/dev.sh build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Terminal/TerminalView.swift
git commit -m "refactor: remove unused terminal attention notification names"
```

---

### Task 16: Update `HelpView` indicator documentation (if present)

**Files:**
- Modify: `Sources/Views/HelpView.swift` (only if it documents the indicator — check first)

- [ ] **Step 1: Check whether the indicator is documented**

Run:

```bash
grep -nE "indicator|pulsing|activity|attention|needs attention" Sources/Views/HelpView.swift
```

If there are no matches: nothing to update. Skip remaining steps in this task and proceed to Task 17.

- [ ] **Step 2: Update the wording (if matches were found)**

Update any text describing the dot to match the new three-state model: pulsing green = working, pulsing accent = waiting, gray = idle, no dot = no agent telemetry. Use the section A table from the spec verbatim if a table is appropriate.

If you edit any user-facing strings, update all 5 `Localizable.strings` files per the localization rules in `CLAUDE.md`.

- [ ] **Step 3: Build, then commit**

Run: `./scripts/dev.sh build`
Then:

```bash
git add Sources/Views/HelpView.swift Localization/
git commit -m "docs(help): describe agent-state indicator"
```

---

### Task 17: Update the architecture reference doc

**Files:**
- Modify: `docs/sidebar-and-toolbar.md`

- [ ] **Step 1: Update the indicator section**

The doc currently describes the title/bell heuristics. Replace the relevant rows in the "Inputs" table and the "Visual signals" table with entries that reflect the new `AgentState`-driven indicator. Use the section A table from the spec.

Suggested replacements for the four affected rows in the "Visual signals" table:

```markdown
| Pulsing **green** dot (left, 12pt slot) | Agent is processing a turn (`AgentState.working`). |
| Pulsing **accent** dot (left) | Agent is waiting for user input (`AgentState.waiting`). |
| Static **gray** dot (left) | Agent's turn ended (`AgentState.idle`). |
| _(no dot)_ | No agent telemetry — either the agent has not been launched yet or the CLI doesn't support hooks (Codex / OpenCode / Gemini). |
```

In the "Inputs" table, replace the `isActive` and `needsAttention` rows with one row:

```markdown
| `agentState` | `AgentStateStore.shared.agentState(for:)` — backed by JSON files written by the `dy-agent-state` helper from Claude Code hooks | `AgentStateStore` watches the directory with kqueue and re-publishes on any change |
```

Remove the sentence "`isActive` and `needsAttention` are the two unreliable signals the agent-state spec replaces" — that's no longer current.

- [ ] **Step 2: Commit**

```bash
git add docs/sidebar-and-toolbar.md
git commit -m "docs: update sidebar reference for agent-state indicator"
```

---

### Task 18: Ship PR 3

- [ ] **Step 1: Run the full test suite one more time**

Run: `./scripts/dev.sh test`
Expected: PASS.

- [ ] **Step 2: Open the PR**

```bash
git push
gh pr create --title "refactor(agent): remove dead activity-tracker plumbing" \
  --body "$(cat <<'EOF'
## Summary

Cleanup after the agent-state indicator cutover.

- Delete `WorkstreamActivityTracker` and its test file (now unused).
- Delete the orphan `terminalNeedsAttention` and `terminalClearAttention` notification name declarations.
- Update the architecture reference doc to describe the new indicator.

Spec: `docs/superpowers/specs/2026-05-17-agent-state-indicator-design.md`

## Test plan

- [ ] `./scripts/dev.sh test` passes
- [ ] App launches and sidebar indicator still behaves as in PR #N+1
EOF
)"
```
