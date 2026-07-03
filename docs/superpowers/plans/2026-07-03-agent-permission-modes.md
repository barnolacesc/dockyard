# Agent Permission Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the agent permission-mode spec so Codex and Claude launch with correct dangerous-mode flags, the UI labels the behavior accurately, and supported live sessions can open native permission controls.

**Architecture:** Keep permission policy mapping in `CodingCLICommandBuilder`, because launch semantics are command-builder behavior and already covered by unit tests. Keep runtime permission controls in `TerminalContainerView` and pass a closure into `WorkstreamInfoView`, so the Info panel stays presentation-focused while the workspace owns terminal injection. Use the existing `TerminalSurfaceCache.sendText(to:text:)` for Codex and a visible Claude hint instead of adding lower-level Ghostty key synthesis in this pass.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen project managed by `project.yml`, localized strings in five `.lproj` files.

---

### Task 1: Command Builder Permission Semantics

**Files:**
- Modify: `Tests/CommandBuilderTests.swift`
- Modify: `Sources/Models/CommandBuilder.swift`

- [ ] **Step 1: Write failing command-builder tests**

Add tests asserting:

```swift
func testBuildCodexAgentCommandBypassUsesDangerousFullAccessFlag()
func testBuildCodexAgentCommandBypassWithHooksKeepsHookTrustSeparate()
func testBuildCodexAgentCommandWithoutBypassUsesPromptedWorkspaceSandbox()
func testBuildCodexAgentCommandWithoutBypassCanAllowOutsideWorktreeWithPrompts()
func testBuildClaudeAgentCommandWithoutBypassAllowsLiveDangerousModeSwitch()
func testBuildClaudeAgentCommandBypassStartsInBypassPermissionMode()
```

Expected assertions:

```swift
XCTAssertTrue(command.intermediateCommands[0].contains("--dangerously-bypass-approvals-and-sandbox"))
XCTAssertFalse(command.intermediateCommands[0].contains("--ask-for-approval"))
XCTAssertFalse(command.intermediateCommands[0].contains("--sandbox"))
XCTAssertTrue(command.intermediateCommands[0].contains("--allow-dangerously-skip-permissions"))
XCTAssertTrue(command.intermediateCommands[0].contains("--permission-mode bypassPermissions"))
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `./scripts/dev.sh test`

Expected: fails in `CommandBuilderTests` because current Codex bypass still emits `--ask-for-approval never --sandbox workspace-write`, and Claude bypass-off does not emit `--allow-dangerously-skip-permissions`.

- [ ] **Step 3: Implement command-builder helpers**

In `Sources/Models/CommandBuilder.swift`, add helpers:

```swift
private static func applyClaudePermissionOptions(to command: inout CommandBuilder, bypassPermissions: Bool) {
    if bypassPermissions {
        command.option("--permission-mode", "bypassPermissions")
    } else {
        command.flag("--allow-dangerously-skip-permissions")
    }
}

private static func applyCodexPermissionOptions(to command: inout CommandBuilder, bypassPermissions: Bool, allowOutsideWorktree: Bool) {
    if bypassPermissions {
        command.flag("--dangerously-bypass-approvals-and-sandbox")
    } else {
        command.option("--sandbox", allowOutsideWorktree ? "danger-full-access" : "workspace-write")
        command.option("--ask-for-approval", "on-request")
    }
}
```

Call the Claude helper for resume and fresh commands. Replace the Codex inline sandbox/approval logic with the Codex helper.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `./scripts/dev.sh test`

Expected: command-builder tests pass.

### Task 2: UI Copy, State, and Localization

**Files:**
- Modify: `Sources/Views/SettingsView.swift`
- Modify: `Sources/Views/WorkstreamInfoView.swift`
- Modify: `Sources/Views/TerminalContainerView.swift`
- Modify: `Localization/en.lproj/Localizable.strings`
- Modify: `Localization/ca.lproj/Localizable.strings`
- Modify: `Localization/de.lproj/Localizable.strings`
- Modify: `Localization/es.lproj/Localizable.strings`
- Modify: `Localization/sv.lproj/Localizable.strings`

- [ ] **Step 1: Update WorkstreamInfoView API**

Add optional runtime controls:

```swift
var livePermissionControlAvailable: Bool = false
var livePermissionHint: String?
var onChangeLivePermissions: () -> Void = {}
```

Replace the old toggle copy with:

```swift
Toggle("Dangerously skip permissions", isOn: $bypassPermissions)
Text("Saved for the next Coding Agent start.")
Button("Change live permissions...", action: onChangeLivePermissions)
```

Show the button only when `livePermissionControlAvailable` is true and show `livePermissionHint` when present.

- [ ] **Step 2: Wire TerminalContainerView state**

Add:

```swift
@State private var livePermissionHint: String?

private var supportsLivePermissionControl: Bool {
    selectedCodingCLI == .claude || selectedCodingCLI == .codex
}

private func openLivePermissionControl() {
    activeTab = .agent
    switch selectedCodingCLI {
    case .codex:
        surfaceCache.sendText(to: agentID, text: "/permissions\r")
        livePermissionHint = nil
    case .claude:
        livePermissionHint = NSLocalizedString("Press Shift+Tab in the Agent tab to switch permission modes.", comment: "")
    case .opencode, .gemini:
        livePermissionHint = NSLocalizedString("Live permission controls are not available for this Coding Agent yet.", comment: "")
    }
}
```

Pass these into `WorkstreamInfoView`.

- [ ] **Step 3: Update Settings copy**

Rename the settings toggle to "Dangerously skip permissions". Update the description to:

```swift
"Starts Coding Agents in their full dangerous mode. Claude Code uses bypassPermissions. Codex bypasses approvals and sandboxing. Use only for trusted workstreams."
```

Disable "Allow writes outside worktree" while dangerous mode is on and show:

```swift
"Ignored while dangerous permission mode is on."
```

- [ ] **Step 4: Add all localized strings**

Add the new English keys and translations to all five locale files.

- [ ] **Step 5: Run tests**

Run: `./scripts/dev.sh test`

Expected: tests pass and SwiftUI compiles.

### Task 3: Final Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run full test suite**

Run: `./scripts/dev.sh test`

Expected: exit 0.

- [ ] **Step 2: Build and run**

Run: `./scripts/dev.sh br`

Expected: debug build succeeds and app launches.

- [ ] **Step 3: Review diff**

Run: `git diff --stat` and `git diff --check`

Expected: scoped changes, no whitespace errors.
