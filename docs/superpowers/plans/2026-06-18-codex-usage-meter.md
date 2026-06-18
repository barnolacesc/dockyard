# Codex Usage Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Codex `/status` usage meter to the Dockyard sidebar and let users cycle between Claude Code and Codex meters.

**Architecture:** Add a small provider-neutral usage model, a Codex `/status` parser/probe/store, and refactor the existing sidebar meter to render either Claude or Codex rows. `ContentView` owns selected-provider state because it already knows the active workstream and effective Coding CLI.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen project generation.

---

## File Structure

- Create `Sources/Models/UsageMeterProvider.swift`: provider enum, shared row/window types, and pure selection helpers.
- Create `Sources/Models/CodexUsageProbe.swift`: parse Codex `/status` output and run a conservative best-effort local probe.
- Create `Sources/Models/CodexUsageStore.swift`: observable throttled store mirroring `ClaudeUsageStore`.
- Modify `Sources/Views/SidebarStatusStrip.swift`: render selected provider, arrow controls, Claude adapter, Codex adapter.
- Modify `Sources/Views/SidebarRail.swift`: use the selected compact meter and padding from the provider-neutral meter.
- Modify `Sources/Views/ContentView.swift`: own `CodexUsageStore`, selected provider, active-provider preference, refresh lifecycle, environment injection.
- Modify all five `Localization/*/Localizable.strings`: add new meter tooltip/control strings.
- Create `Tests/CodexUsageProbeTests.swift`: parser and Codex percent-left conversion tests.
- Create `Tests/UsageMeterProviderTests.swift`: provider mapping, cycling, and selection tests.

## Task 1: Shared Usage Provider Helpers

**Files:**
- Create: `Sources/Models/UsageMeterProvider.swift`
- Test: `Tests/UsageMeterProviderTests.swift`

- [ ] **Step 1: Write failing provider tests**

Add `Tests/UsageMeterProviderTests.swift`:

```swift
@testable import Dockyard
import XCTest

final class UsageMeterProviderTests: XCTestCase {
    func testPreferredProviderMapsSupportedCodingCLIs() {
        XCTAssertEqual(UsageMeterProvider.preferred(for: .claude), .claude)
        XCTAssertEqual(UsageMeterProvider.preferred(for: .codex), .codex)
        XCTAssertNil(UsageMeterProvider.preferred(for: .opencode))
        XCTAssertNil(UsageMeterProvider.preferred(for: .gemini))
    }

    func testCyclingWrapsThroughAvailableProviders() {
        let providers: [UsageMeterProvider] = [.claude, .codex]
        XCTAssertEqual(cycledUsageMeterProvider(current: .claude, available: providers, direction: 1), .codex)
        XCTAssertEqual(cycledUsageMeterProvider(current: .codex, available: providers, direction: 1), .claude)
        XCTAssertEqual(cycledUsageMeterProvider(current: .claude, available: providers, direction: -1), .codex)
    }

    func testResolvedSelectionUsesPreferredProviderWhenItChanges() {
        let selection = resolvedUsageMeterProvider(
            current: .claude,
            preferred: .codex,
            previousPreferred: .claude,
            available: [.claude, .codex]
        )
        XCTAssertEqual(selection, .codex)
    }

    func testResolvedSelectionKeepsManualSelectionWhenPreferredDoesNotChange() {
        let selection = resolvedUsageMeterProvider(
            current: .codex,
            preferred: .claude,
            previousPreferred: .claude,
            available: [.claude, .codex]
        )
        XCTAssertEqual(selection, .codex)
    }

    func testResolvedSelectionFallsBackWhenCurrentUnavailable() {
        let selection = resolvedUsageMeterProvider(
            current: .codex,
            preferred: .claude,
            previousPreferred: .claude,
            available: [.claude]
        )
        XCTAssertEqual(selection, .claude)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/dev.sh test`

Expected: FAIL because `UsageMeterProvider`, `cycledUsageMeterProvider`, and `resolvedUsageMeterProvider` are not defined.

- [ ] **Step 3: Implement shared provider helpers**

Add `Sources/Models/UsageMeterProvider.swift`:

```swift
import Foundation

enum UsageMeterProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:
            return CodingCLI.claude.displayName
        case .codex:
            return CodingCLI.codex.displayName
        }
    }

    static func preferred(for cli: CodingCLI) -> UsageMeterProvider? {
        switch cli {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .opencode, .gemini:
            return nil
        }
    }
}

struct UsageMeterWindow: Equatable {
    var percentUsed: Int?
    var tokens: Int?
    var resetText: String?
}

struct UsageMeterSnapshot: Equatable {
    var provider: UsageMeterProvider
    var displayName: String
    var current: UsageMeterWindow?
    var weekly: UsageMeterWindow?
}

func cycledUsageMeterProvider(
    current: UsageMeterProvider,
    available: [UsageMeterProvider],
    direction: Int
) -> UsageMeterProvider {
    guard !available.isEmpty,
          let index = available.firstIndex(of: current)
    else {
        return available.first ?? current
    }
    let next = (index + direction + available.count) % available.count
    return available[next]
}

func resolvedUsageMeterProvider(
    current: UsageMeterProvider,
    preferred: UsageMeterProvider?,
    previousPreferred: UsageMeterProvider?,
    available: [UsageMeterProvider]
) -> UsageMeterProvider {
    if let preferred,
       preferred != previousPreferred,
       available.contains(preferred) {
        return preferred
    }
    if available.contains(current) {
        return current
    }
    if let preferred, available.contains(preferred) {
        return preferred
    }
    return available.first ?? current
}
```

- [ ] **Step 4: Run tests to verify Task 1 passes**

Run: `./scripts/dev.sh test`

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/Models/UsageMeterProvider.swift Tests/UsageMeterProviderTests.swift
git commit -m "feat: add usage meter provider selection"
```

## Task 2: Codex `/status` Parser

**Files:**
- Create: `Sources/Models/CodexUsageProbe.swift`
- Test: `Tests/CodexUsageProbeTests.swift`

- [ ] **Step 1: Write failing parser tests**

Add `Tests/CodexUsageProbeTests.swift`:

```swift
@testable import Dockyard
import XCTest

final class CodexUsageProbeTests: XCTestCase {
    private let sample = """
    OpenAI Codex (v0.139.0)

    Model:                gpt-5.5 (reasoning high, summaries auto)
    Account:              user@example.com (Plus)

    5h limit:             [##############------] 68% left
                          (resets 01:29 on 19 Jun)
    Weekly limit:         [#################---] 85% left
                          (resets 23:30 on 24 Jun)
    """

    func testParsesLimitRowsAndResetText() {
        let report = CodexUsageProbe.parseText(sample)
        XCTAssertEqual(report?.fiveHour?.percentLeft, 68)
        XCTAssertEqual(report?.fiveHour?.resetText, "01:29 on 19 Jun")
        XCTAssertEqual(report?.week?.percentLeft, 85)
        XCTAssertEqual(report?.week?.resetText, "23:30 on 24 Jun")
    }

    func testParsesModelAndAccount() {
        let report = CodexUsageProbe.parseText(sample)
        XCTAssertEqual(report?.model, "gpt-5.5 (reasoning high, summaries auto)")
        XCTAssertEqual(report?.account, "user@example.com (Plus)")
    }

    func testReturnsNilWhenNoLimitRows() {
        XCTAssertNil(CodexUsageProbe.parseText("Model: gpt-5.5\\nNo usage here"))
    }

    func testToleratesANSIEscapeSequences() {
        let text = "\\u{001B}[2m5h limit:\\u{001B}[0m [####------] \\u{001B}[1m68% left\\u{001B}[0m\\n(resets 01:29 on 19 Jun)"
        let report = CodexUsageProbe.parseText(text)
        XCTAssertEqual(report?.fiveHour?.percentLeft, 68)
        XCTAssertEqual(report?.fiveHour?.resetText, "01:29 on 19 Jun")
    }

    func testConvertsPercentLeftToPercentUsed() {
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 68), 32)
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 0), 100)
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 100), 0)
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 140), 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/dev.sh test`

Expected: FAIL because `CodexUsageProbe` is not defined.

- [ ] **Step 3: Implement parser and best-effort probe**

Add `Sources/Models/CodexUsageProbe.swift`:

```swift
import Foundation

struct CodexUsageReport: Equatable {
    struct Window: Equatable {
        var percentLeft: Int
        var resetText: String?
    }

    var model: String?
    var account: String?
    var fiveHour: Window?
    var week: Window?

    var isEmpty: Bool {
        fiveHour == nil && week == nil
    }
}

enum CodexUsageProbe {
    static func fetch(shell: String = CommandBuilder.userShell) -> CodexUsageReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [
            "-lic",
            "printf '/status\\r/quit\\r' | script -q /dev/null codex --no-alt-screen"
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> CodexUsageReport? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parseText(text)
    }

    static func parseText(_ text: String) -> CodexUsageReport? {
        let lines = stripANSI(text)
            .split(whereSeparator: { $0 == "\\n" || $0 == "\\r" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var report = CodexUsageReport()
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if lower.hasPrefix("model:") {
                report.model = value(afterColonIn: line)
            } else if lower.hasPrefix("account:") {
                report.account = value(afterColonIn: line)
            } else if lower.contains("5h limit:"),
                      let percent = percentLeft(in: line) {
                report.fiveHour = CodexUsageReport.Window(
                    percentLeft: percent,
                    resetText: resetText(after: index, in: lines)
                )
            } else if lower.contains("weekly limit:"),
                      let percent = percentLeft(in: line) {
                report.week = CodexUsageReport.Window(
                    percentLeft: percent,
                    resetText: resetText(after: index, in: lines)
                )
            }
        }

        return report.isEmpty ? nil : report
    }

    static func percentUsed(fromPercentLeft percentLeft: Int) -> Int {
        max(0, min(100, 100 - percentLeft))
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func value(afterColonIn line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func percentLeft(in line: String) -> Int? {
        guard let range = line.range(of: #"\d+\s*%\s*left"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(line[range])
        guard let percentRange = match.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(match[percentRange])
    }

    private static func resetText(after index: Int, in lines: [String]) -> String? {
        let nextIndex = index + 1
        guard lines.indices.contains(nextIndex) else { return nil }
        let line = lines[nextIndex]
        guard let range = line.range(of: #"resets\s+([^)]+)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var text = String(line[range])
        text = text.replacingOccurrences(of: #"(?i)^resets\s+"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespacesAndNewlines))
        return text.isEmpty ? nil : text
    }
}
```

- [ ] **Step 4: Run tests to verify Task 2 passes**

Run: `./scripts/dev.sh test`

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/Models/CodexUsageProbe.swift Tests/CodexUsageProbeTests.swift
git commit -m "feat: parse codex usage status"
```

## Task 3: Codex Store and Sidebar Rendering

**Files:**
- Create: `Sources/Models/CodexUsageStore.swift`
- Modify: `Sources/Views/SidebarStatusStrip.swift`
- Modify: `Sources/Views/SidebarRail.swift`
- Modify: `Sources/Views/ContentView.swift`
- Modify: `Localization/en.lproj/Localizable.strings`
- Modify: `Localization/ca.lproj/Localizable.strings`
- Modify: `Localization/de.lproj/Localizable.strings`
- Modify: `Localization/es.lproj/Localizable.strings`
- Modify: `Localization/sv.lproj/Localizable.strings`

- [ ] **Step 1: Implement Codex store**

Create `Sources/Models/CodexUsageStore.swift`:

```swift
import Foundation

@MainActor
final class CodexUsageStore: ObservableObject {
    static let shared = CodexUsageStore()

    @Published private(set) var report: CodexUsageReport?

    private static let minProbeInterval: TimeInterval = 300
    private var lastProbe: Date?
    private var isRefreshing = false

    init() {
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        let now = Date()
        let doProbe = force || lastProbe == nil || now.timeIntervalSince(lastProbe!) >= Self.minProbeInterval
        guard doProbe, !isRefreshing else { return }

        isRefreshing = true
        lastProbe = now

        Task.detached(priority: .utility) {
            let report = CodexUsageProbe.fetch()
            await MainActor.run {
                if let report { self.report = report }
                self.isRefreshing = false
            }
        }
    }

    var hasAnyData: Bool {
        report != nil
    }
}
```

- [ ] **Step 2: Refactor `SidebarUsageMeter` to accept provider inputs**

Modify `Sources/Views/SidebarStatusStrip.swift` so `SidebarStatusStrip` accepts:

```swift
let selectedUsageProvider: UsageMeterProvider
let availableUsageProviders: [UsageMeterProvider]
let onPreviousUsageProvider: () -> Void
let onNextUsageProvider: () -> Void
```

and passes them into:

```swift
SidebarUsageMeter(
    style: .expanded,
    selectedProvider: selectedUsageProvider,
    availableProviders: availableUsageProviders,
    onPreviousProvider: onPreviousUsageProvider,
    onNextProvider: onNextUsageProvider
)
```

Give the new properties defaults so previews/old call sites compile:

```swift
var selectedUsageProvider: UsageMeterProvider = .claude
var availableUsageProviders: [UsageMeterProvider] = [.claude]
var onPreviousUsageProvider: () -> Void = {}
var onNextUsageProvider: () -> Void = {}
```

- [ ] **Step 3: Add Codex rendering path**

In `SidebarUsageMeter`, add:

```swift
@EnvironmentObject private var codexUsageStore: CodexUsageStore
let selectedProvider: UsageMeterProvider
let availableProviders: [UsageMeterProvider]
let onPreviousProvider: () -> Void
let onNextProvider: () -> Void
```

Update `hasAnyData`, refresh click, tooltip, header provider label, current row,
and weekly row to switch on `selectedProvider`. Codex rows use:

```swift
let percentUsed = CodexUsageProbe.percentUsed(fromPercentLeft: window.percentLeft)
```

and `fraction: Double(percentUsed) / 100`.

- [ ] **Step 4: Wire compact rail meter**

Modify `Sources/Views/SidebarRail.swift`:

```swift
@EnvironmentObject private var codexUsageStore: CodexUsageStore
```

and call:

```swift
SidebarUsageMeter(
    style: .compact,
    selectedProvider: .claude,
    availableProviders: [.claude],
    onPreviousProvider: {},
    onNextProvider: {}
)
```

The collapsed rail stays minimal in this iteration; `ContentView` controls expanded sidebar cycling.

- [ ] **Step 5: Wire ContentView state and refresh**

Modify `Sources/Views/ContentView.swift`:

- Add `@StateObject private var codexUsageStore = CodexUsageStore.shared`
- Add `@State private var selectedUsageProvider: UsageMeterProvider = .claude`
- Add `@State private var previousPreferredUsageProvider: UsageMeterProvider?`
- Inject `.environmentObject(codexUsageStore)`
- Refresh `codexUsageStore` anywhere `claudeUsageStore.refresh()` is called.
- Compute preferred provider from the active workstream's effective CLI.
- Pass selected/available providers and arrow callbacks into `ProjectSidebar`, then through to `SidebarStatusStrip` if needed. If `ProjectSidebar` owns the status strip call, add matching parameters there with defaults.

- [ ] **Step 6: Add localization strings**

Add these keys to all five `Localizable.strings` files:

```text
"Previous usage meter" = "...";
"Next usage meter" = "...";
"Real usage from Codex /status. Click to refresh." = "...";
```

Use English for `en`, direct translations for the other locale files, and preserve existing style.

- [ ] **Step 7: Run tests**

Run: `./scripts/dev.sh test`

Expected: PASS.

- [ ] **Step 8: Commit Task 3**

```bash
git add Sources/Models/CodexUsageStore.swift Sources/Views/SidebarStatusStrip.swift Sources/Views/SidebarRail.swift Sources/Views/ContentView.swift Sources/Views/ProjectSidebar.swift Localization/*/Localizable.strings
git commit -m "feat: add codex usage meter"
```

## Task 4: Final Build Verification

**Files:**
- No planned file changes.

- [ ] **Step 1: Regenerate project if needed**

Run: `xcodegen generate`

Expected: project generation succeeds. This is required because new Swift source and test files were added.

- [ ] **Step 2: Run full test suite**

Run: `./scripts/dev.sh test`

Expected: PASS.

- [ ] **Step 3: Run debug build**

Run: `./scripts/dev.sh build`

Expected: PASS.

- [ ] **Step 4: Inspect git status**

Run: `git status --short`

Expected: only intentional source/test/localization/plan changes, or clean if all task commits were made.
