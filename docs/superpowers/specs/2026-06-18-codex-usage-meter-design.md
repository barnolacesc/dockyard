# Codex Usage Meter

**Date:** 2026-06-18
**Status:** Approved design

## Problem

Dockyard has a sidebar usage meter for Claude Code. Users who run Codex as the
Coding Agent need the same at-a-glance signal: current short-window usage,
weekly usage, reset times, and a way to switch between installed AI-provider
meters.

The meter should follow the focused workspace's Coding Agent by default. If the
focused workstream uses Codex, show Codex usage. If it uses Claude Code, show
Claude usage. The user can also manually cycle through available meters with
back/next arrows in the sidebar meter area.

## Context

Claude usage is already implemented through `ClaudeUsageStore`,
`ClaudeUsageProbe`, and `SidebarUsageMeter`.

Codex's documented slash commands vary by version. Current docs describe
`/usage` as account usage, but the locally verified Codex CLI v0.139.0 does not
recognize `/usage` and does expose usage limits through `/status`.

The verified `/status` output includes:

```text
5h limit:             [##############------] 68% left
                      (resets 01:29 on 19 Jun)
Weekly limit:         [#################---] 85% left
                      (resets 23:30 on 24 Jun)
```

It also includes model/account metadata, for example:

```text
Model:                gpt-5.5 (reasoning high, summaries auto)
Account:              user@example.com (Plus)
```

## Goals

- Add a Codex usage meter using Codex `/status` as the source of truth.
- Preserve the existing Claude meter behavior.
- Show usage in a consistent Dockyard format across providers.
- Default the visible meter to the active/focused workstream's Coding Agent.
- Add small previous/next arrow buttons in the sidebar meter to cycle through
  available provider meters.
- Keep the provider-meter system ready for future agents without implementing
  Gemini or OpenCode usage now.

## Non-Goals

- Implement Gemini or OpenCode meters.
- Open the ChatGPT usage settings page from the meter.
- Replace the existing Claude transcript estimate fallback.
- Add a full settings screen for meter ordering or provider visibility.
- Fetch Codex enterprise analytics or call web APIs.

## Decisions

- **Codex source:** run Codex in a PTY-style probe, send `/status`, parse the
  visible text, then exit. `/status` is used because it is the behavior verified
  in the user's installed CLI.
- **Codex percentage semantics:** Codex reports `% left`; Dockyard displays
  `% used` to match the existing Claude meter style. For example, `68% left`
  displays as `32% used`.
- **Provider switching:** the sidebar has a selected provider (`claude` or
  `codex`). It follows the active workstream's effective `CodingCLI` unless the
  user manually cycles with the arrows. When the user cycles, the selected
  provider persists until the active provider changes or the provider becomes
  unavailable.
- **Available meters:** for this iteration, available means the provider has a
  meter implementation and either installed-tool status or existing usage data:
  Claude Code and Codex only.

## User Experience

Expanded sidebar target:

```text
      Usage                         Codex
  <   32% used   Current            >
      [######--------------]
      resets 01:29 on 19 Jun

      15% used   Weekly
      [###-----------------]
      resets 23:30 on 24 Jun
```

The arrows are icon buttons (`chevron.left` and `chevron.right`) positioned on
the sides of the meter header or the first row, depending on what fits cleanly
in the current sidebar width. They should not push text around as values change.

Compact/collapsed sidebar:

- Continue showing the compact usage meter.
- Use the selected provider.
- Keep controls minimal; if arrows do not fit in collapsed mode, omit them there
  and keep cycling available only in expanded mode.

Interactions:

- Click the meter body to refresh the currently selected provider.
- Click previous/next arrows to cycle provider meters.
- Tooltip explains the source:
  - Claude: real Claude `/usage` when available, otherwise transcript estimate.
  - Codex: real Codex `/status` output.

## Architecture

### 1. Shared meter data

Introduce a small provider-neutral representation in a new model file, for
example `Sources/Models/UsageMeterProvider.swift`:

```swift
enum UsageMeterProvider: String, CaseIterable, Identifiable {
    case claude
    case codex
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
```

Keep this representation UI-oriented. It should not replace
`ClaudeUsageReport`, `ClaudeUsageSnapshot`, or their parser types.

### 2. Codex parser and probe

Add `Sources/Models/CodexUsageProbe.swift`:

```swift
struct CodexUsageReport: Equatable {
    struct Window: Equatable {
        var percentLeft: Int
        var resetText: String?
    }

    var model: String?
    var account: String?
    var fiveHour: Window?
    var week: Window?
}
```

Parser responsibilities:

- Strip ANSI escape codes and box-drawing noise where needed.
- Parse `Model:` and `Account:` when present.
- Parse rows containing `5h limit:` and `Weekly limit:`.
- Extract the first integer followed by `% left`.
- Extract the following reset line in the form `(resets ...)`.
- Return `nil` when no limit rows are found.

Probe responsibilities:

- Run Codex through the user's login shell or the resolved Codex path in a way
  that allows slash-command interaction.
- Prefer `codex --no-alt-screen` so output remains visible in scrollback.
- Send `/status\r`, wait briefly for output, send `/quit\r`, then parse.
- Avoid starting a prompt or model turn. The probe must only use the local slash
  command UI.
- Run off the main actor and throttle like the Claude probe.

If probing Codex fails because of an update prompt, PTY issue, missing binary,
or changed UI format, keep the previous good report and hide Codex data if no
report has ever been parsed.

### 3. Codex store

Add `CodexUsageStore: ObservableObject`:

- `static let shared = CodexUsageStore()`
- `@Published private(set) var report: CodexUsageReport?`
- `refresh(force:)` with a probe throttle similar to `ClaudeUsageStore`
- `hasAnyData` derived from `report != nil`

The store does not need a transcript fallback in this iteration.

### 4. Sidebar selection state

Add provider selection state where the sidebar can see both the active
workstream and the usage stores. `ContentView` is the likely owner because it
already knows `activeWorkstream`, the global `dockyard.codingCLI`, and the
effective per-workstream override.

Data flow:

```text
active workstream + global default + per-workstream override
        |
        v
effective CodingCLI
        |
        v
preferred UsageMeterProvider (.claude / .codex when supported)
        |
        v
SidebarStatusStrip(selectedProvider, availableProviders)
```

Rules:

- When the active effective CLI maps to a supported provider, select that
  provider.
- Manual arrow cycling changes `selectedProvider`.
- If the active effective CLI changes to a different supported provider, update
  `selectedProvider` to match it.
- If the selected provider is no longer available, fall back to the preferred
  provider, then the first available provider.

### 5. Sidebar UI

Refactor `SidebarUsageMeter` so it receives:

- selected provider
- available providers
- callbacks for previous/next
- both usage stores via environment or explicit parameters

Rendering behavior:

- Claude provider reuses existing `currentRow` and `weeklyRow` logic.
- Codex provider renders:
  - Current: `100 - percentLeft`
  - Weekly: `100 - percentLeft`
  - Same bar component as Claude
  - Same reset subtitle formatting
- Header shows `Usage` and the provider display name (`Claude Code` or `Codex`).
- Arrows appear only when more than one provider meter is available.

### 6. Refresh lifecycle

`ContentView` already refreshes `claudeUsageStore` on the 15s app timer.
Extend the lifecycle so Codex usage also refreshes:

- on app/view appear
- on the existing periodic timer, throttled by `CodexUsageStore`
- on meter click with `force: true`

The Codex probe may be heavier than the Claude parser, so use a conservative
minimum interval, for example 3-5 minutes, while still allowing forced refresh.

### 7. Localization

Add new user-facing strings to all five locale files:

- `Codex status source tooltip`
- `Previous usage meter`
- `Next usage meter`
- Any new provider header format if not assembled from existing localized names

Existing strings like `Usage`, `Current`, `Weekly`, `resets %@`, and provider
display names should be reused.

## Testing

Follow TDD for implementation.

Add parser tests in a new `Tests/CodexUsageProbeTests.swift`:

- Parses `5h limit` and `Weekly limit` percentages from verified `/status`
  output.
- Converts Codex `% left` to UI `% used` through the adapter/render-model helper.
- Parses reset text from the line after each limit row.
- Parses model and account when present.
- Returns `nil` for unrelated text.
- Tolerates ANSI escape sequences around the report.

Add selection/cycling tests if the provider-selection logic is extracted as pure
helpers:

- Active Codex workstream selects Codex.
- Active Claude workstream selects Claude.
- Manual next/previous cycles through available providers.
- Unsupported active CLI keeps or falls back to the current available provider.

Run:

```bash
./scripts/dev.sh test
./scripts/dev.sh build
```

If new Swift files are added, run `xcodegen generate` before building.

## Risks

- Codex `/status` is a TUI slash command, not a stable JSON API. Mitigation:
  keep parsing isolated, tolerant, and covered by fixtures from real output.
- Codex update prompts can block the probe. Mitigation: fail closed, keep the
  last good report, and allow manual refresh later.
- The probe must not accidentally submit a prompt. Mitigation: use `/status`
  only, assert parser tests around captured command output, and keep subprocess
  control isolated.
- Docs and local CLI behavior differ. Mitigation: use the verified local
  behavior for this feature and document the decision in this spec.

## Acceptance Criteria

- A workstream using Codex shows a Codex usage meter in the sidebar.
- A workstream using Claude Code shows the existing Claude usage meter.
- The arrows cycle between Claude Code and Codex meters when both are available.
- Codex current and weekly values show as `% used`, with reset text when parsed.
- Clicking the visible meter refreshes that provider.
- Existing Claude usage behavior and compact sidebar behavior do not regress.
