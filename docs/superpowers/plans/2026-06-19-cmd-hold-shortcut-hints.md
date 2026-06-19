# Cmd-Hold Shortcut Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show contextual shortcut badges over visible Dockyard controls while Command is held, with live Shift/Option variants and a default-on setting.

**Architecture:** A main-actor controller observes modifier, key-down, activation, and preference changes without consuming events. Descendant views publish bounds plus typed shortcut metadata through an anchor preference; `ContentView` resolves and draws all currently visible badges in one non-interactive overlay.

**Tech Stack:** Swift 6, SwiftUI anchor preferences, AppKit `NSEvent`, XCTest, XcodeGen.

---

### Task 1: Test and implement shortcut state and matching

**Files:**
- Create: `Tests/ShortcutHintsTests.swift`
- Create: `Sources/Views/ShortcutHints.swift`

- [ ] **Step 1: Write failing reducer and lookup tests**

Add XCTest cases that assert:

```swift
@MainActor
func testCommandActivatesHints() {
    let state = ShortcutHintState.reduce(flags: [.command], enabled: true)
    XCTAssertTrue(state.isActive)
    XCTAssertEqual(state.activeModifiers, [.command])
}

@MainActor
func testReducerNormalizesShiftAndOptionAndIgnoresOtherFlags() {
    XCTAssertEqual(
        ShortcutHintState.reduce(flags: [.command, .shift, .capsLock], enabled: true).activeModifiers,
        [.command, .shift]
    )
    XCTAssertEqual(
        ShortcutHintState.reduce(flags: [.command, .option, .control], enabled: true).activeModifiers,
        [.command, .option]
    )
}

@MainActor
func testReducerRequiresCommandAndEnabledSetting() {
    XCTAssertFalse(ShortcutHintState.reduce(flags: [.shift], enabled: true).isActive)
    XCTAssertFalse(ShortcutHintState.reduce(flags: [.command], enabled: false).isActive)
}

@MainActor
func testHintReturnsOnlyExactModifierVariant() {
    let hint = ShortcutHint(command: "R", commandShift: "R")
    XCTAssertEqual(hint.badge(for: [.command]), KeyBadge(key: "R", modifiers: [.command]))
    XCTAssertEqual(hint.badge(for: [.command, .shift]), KeyBadge(key: "R", modifiers: [.command, .shift]))
    XCTAssertNil(hint.badge(for: [.command, .option]))
}
```

- [ ] **Step 2: Regenerate and run the focused tests to verify failure**

Run: `xcodegen generate && ./scripts/dev.sh test -only-testing:DockyardTests/ShortcutHintsTests`

Expected: build failure because `ShortcutHintState`, `ShortcutHint`, and `KeyBadge` do not exist.

- [ ] **Step 3: Add the pure model and controller**

Implement in `ShortcutHints.swift`:

```swift
struct ShortcutHintState: Equatable {
    let isActive: Bool
    let activeModifiers: NSEvent.ModifierFlags

    static func reduce(flags: NSEvent.ModifierFlags, enabled: Bool) -> Self {
        let normalized = flags.intersection([.command, .shift, .option])
        return Self(
            isActive: enabled && normalized.contains(.command),
            activeModifiers: normalized
        )
    }
}

struct KeyBadge: Equatable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
}

struct ShortcutHint {
    private let badges: [NSEvent.ModifierFlags: KeyBadge]
    // Convenience initialization for Command, Command-Shift, and Command-Option variants.
    func badge(for modifiers: NSEvent.ModifierFlags) -> KeyBadge? { badges[modifiers] }
}
```

Add `@MainActor final class ShortcutHintController: ObservableObject` with published state, idempotent `start()`, retained local monitor tokens and resign-active observer, `setEnabled(_:)`, and `stop()` cleanup. Every local monitor must return its input event. `.flagsChanged` reduces state, `.keyDown` dismisses active hints, and app resignation dismisses hints.

- [ ] **Step 4: Run focused tests**

Run: `./scripts/dev.sh test -only-testing:DockyardTests/ShortcutHintsTests`

Expected: all `ShortcutHintsTests` pass.

- [ ] **Step 5: Commit the model and tests**

```bash
git add project.yml Dockyard.xcodeproj Sources/Views/ShortcutHints.swift Tests/ShortcutHintsTests.swift
git commit -m "feat: add shortcut hint state controller"
```

### Task 2: Add anchor collection and root overlay

**Files:**
- Modify: `Sources/Views/ShortcutHints.swift`
- Modify: `Sources/DockyardApp.swift`
- Modify: `Sources/Views/ContentView.swift`

- [ ] **Step 1: Add anchor preference plumbing**

Define a preference entry containing a stable UUID, `Anchor<CGRect>`, and `ShortcutHint`; define a preference key that merges entries by UUID. Add `View.shortcutHint(_:)`, backed by a modifier with a state-owned UUID, to publish each annotated view's bounds.

- [ ] **Step 2: Add the non-interactive overlay**

Add `ShortcutHintOverlay` that resolves collected anchors in a `GeometryReader`, chooses the exact badge for `controller.activeModifiers`, and places each `HintBadge` at the anchor's top-trailing corner. Render command/option/shift SF Symbols in modifier order followed by monospaced key text, use a regular-material capsule and subtle shadow, disable hit testing, and animate opacity over 0.1 seconds.

- [ ] **Step 3: Install the controller once at the app root**

Create `@StateObject private var shortcutHints = ShortcutHintController()` in `DockyardApp`, inject it beside `updater`, and call `start()` from the main content's `onAppear`. Apply the overlay around `ContentView` so anchors from sidebar and detail descendants share one coordinate space.

- [ ] **Step 4: Build to catch preference and actor-isolation errors**

Run: `./scripts/dev.sh build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit the rendering infrastructure**

```bash
git add Sources/DockyardApp.swift Sources/Views/ContentView.swift Sources/Views/ShortcutHints.swift
git commit -m "feat: render contextual shortcut hint badges"
```

### Task 3: Annotate workspace, sidebar, browser, and editor controls

**Files:**
- Modify: `Sources/Views/TerminalContainerView.swift`
- Modify: `Sources/Views/EnvironmentTabView.swift`
- Modify: `Sources/Views/ProjectSidebar.swift`
- Modify: `Sources/Views/BrowserView.swift`
- Modify: `Sources/Views/EditorView.swift`

- [ ] **Step 1: Annotate workspace tabs and tab creation controls**

In `tabButton(for:)`, derive the visible tab index and attach Command-1 through Command-9 hints. Attach Command-T/Command-Shift-T, Command-B/Command-Shift-B, and Command-O hints to the three `TabBarActionButton` instances.

- [ ] **Step 2: Annotate visible run actions**

Attach Command-Shift-Return to every visible Start or Rerun control in `EnvironmentTabView`, including compact action buttons and empty-state Start buttons. Stop has no shortcut hint.

- [ ] **Step 3: Annotate sidebar navigation targets**

Attach Command-Up/Down to the selected project row, Command-LeftBracket/RightBracket plus Command-Shift-W to the selected workstream row, and Command-N/Command-Shift-N to the bottom add-project menu. Represent paired directional keys in one badge string (`"↑ ↓"` and `"[ ]"`).

- [ ] **Step 4: Annotate browser and editor chrome**

Attach Command-R/Command-Shift-R to browser reload and Command-L to its URL field. Attach Command-S/Command-Shift-S to the editor toolbar, which is the visible chrome associated with the existing save commands; do not add a new action or keybinding.

- [ ] **Step 5: Build the annotated UI**

Run: `./scripts/dev.sh build`

Expected: `** BUILD SUCCEEDED **` with no generic-view or modifier inference errors.

- [ ] **Step 6: Commit annotations**

```bash
git add Sources/Views/TerminalContainerView.swift Sources/Views/EnvironmentTabView.swift Sources/Views/ProjectSidebar.swift Sources/Views/BrowserView.swift Sources/Views/EditorView.swift
git commit -m "feat: annotate controls with shortcut hints"
```

### Task 4: Add the setting and all localizations

**Files:**
- Modify: `Sources/Views/SettingsView.swift`
- Modify: `Localization/en.lproj/Localizable.strings`
- Modify: `Localization/ca.lproj/Localizable.strings`
- Modify: `Localization/de.lproj/Localizable.strings`
- Modify: `Localization/es.lproj/Localizable.strings`
- Modify: `Localization/sv.lproj/Localizable.strings`

- [ ] **Step 1: Add the default-on setting**

Add `@AppStorage("dockyard.showShortcutHints") private var showShortcutHints = true`, access the controller through `@EnvironmentObject`, and add this `SettingToggle` to General settings:

```swift
SettingToggle(
    "Show shortcut hints while holding ⌘",
    isOn: $showShortcutHints,
    description: "Display contextual key badges over visible controls when you hold the Command key."
)
.onChange(of: showShortcutHints) { _, enabled in
    shortcutHints.setEnabled(enabled)
}
```

- [ ] **Step 2: Localize both strings in all five locales**

Add accurate English, Catalan, German, Spanish, and Swedish translations for the toggle label and description. Preserve UTF-8 Command glyphs and existing `.strings` formatting.

- [ ] **Step 3: Build and run all unit tests**

Run: `./scripts/dev.sh test`

Expected: all XCTest suites pass.

- [ ] **Step 4: Commit settings and localization**

```bash
git add Sources/Views/SettingsView.swift Localization/*/Localizable.strings
git commit -m "feat: add shortcut hints setting"
```

### Task 5: Final verification

**Files:**
- Review all files changed above.

- [ ] **Step 1: Regenerate because source and test files were added**

Run: `xcodegen generate`

Expected: project generation succeeds and includes `ShortcutHints.swift` and `ShortcutHintsTests.swift`.

- [ ] **Step 2: Run project-required build and launch**

Run: `./scripts/dev.sh br`

Expected: debug build succeeds and Dockyard Debug launches.

- [ ] **Step 3: Perform the manual interaction checks**

Verify Command instantly shows hints; Shift and Option live-swap exact variants; key-down, Command release, and app deactivation dismiss; terminal typing and existing shortcuts still work; the setting disables and re-enables hints; badges track scrolling, resizing, and tab switches without intercepting clicks.

- [ ] **Step 4: Run the full test suite once more after manual checks**

Run: `./scripts/dev.sh test`

Expected: all tests pass.

- [ ] **Step 5: Review the diff and repository state**

Run: `git diff origin/main...HEAD --check && git status --short`

Expected: no whitespace errors; only intended implementation files, generated project updates, and this plan differ.
