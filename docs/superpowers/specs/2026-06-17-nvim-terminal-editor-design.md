# Terminal editor (open Neovim instead of Monaco)

**Date:** 2026-06-17
**Status:** Approved, ready for implementation plan

## Problem

The "editor" tab (Cmd+O / the "New Editor" toolbar button) opens the embedded
Monaco code editor — an IDE-like WKWebView. Some users prefer to edit in their
own terminal editor (Neovim). There is currently no way to do this: Cmd+O always
opens Monaco.

## Goal

Add an opt-in setting so that Cmd+O / "New Editor" opens a configurable terminal
editor command (defaulting to `nvim .`) in an in-app terminal tab, instead of the
Monaco editor. When the setting is off, behavior is unchanged.

## Non-goals

- Replacing or removing the Monaco editor. It remains the default.
- Launching an external terminal app. The editor opens as an in-app tab.
- Per-project or per-workstream editor configuration. The setting is global.
- Persisting the nvim tab across full app restarts (editor/terminal tabs already
  do not survive a real restart — only in-session navigation).

## User-facing behavior

Two new settings in **Settings → General**:

1. **Toggle** "Open editor in a terminal" — `dockyard.useTerminalEditor`, default
   `false`.
2. **Command field** "Editor command" — `dockyard.terminalEditorCommand`, default
   `"nvim ."`. Shown/enabled only when the toggle is on. Styled like the existing
   "Branch prefix" field (`TextField`, `.roundedBorder`, capped width).

Behavior:

- **Toggle off (default):** Cmd+O and the "New Editor" toolbar button open the
  Monaco editor tab — exactly as today. No behavioral change.
- **Toggle on:** Cmd+O and "New Editor" open an in-app terminal tab that runs the
  configured command in the worktree directory. The default `nvim .` opens Neovim
  with the worktree folder loaded.

When the user quits the editor (`:q`), the terminal surface falls back to a shell
(`wait_after_command = true`, consistent with the Coding Agent and regular terminal
tabs). Ctrl+D or Cmd+W closes the tab.

## Architecture

The Coding Agent tab is already a terminal surface that runs a command (`claude`)
via `SingleTerminalView(..., command:)`. Regular terminal tabs pass no command and
get the default shell. The terminal editor reuses this exact path: a terminal tab
that runs the editor command.

### Components touched

All in `Sources/Views/TerminalContainerView.swift` unless noted.

1. **New state map** on `TerminalContainerView`:
   `@State private var terminalEditorCommands: [UUID: String] = [:]`
   Maps a terminal tab's id to the editor command it was opened with. Only editor
   terminals have an entry; regular terminals do not. This map is the single source
   of truth for "is this terminal tab an editor terminal?".

2. **New `@AppStorage` reads** on `TerminalContainerView`:
   - `dockyard.useTerminalEditor` (Bool)
   - `dockyard.terminalEditorCommand` (String)

3. **`openEditor()`** branches on the toggle:
   ```
   private func openEditor() {
       if useTerminalEditor {
           addTerminalEditor()
       } else {
           addEditor()   // existing Monaco path, unchanged
       }
   }
   ```

4. **New `addTerminalEditor()`** — mirrors `addTerminal()` but records the command:
   ```
   private func addTerminalEditor() {
       terminalCount += 1
       let id = derivedUUID(from: workstreamID, salt: "terminal-\(terminalCount)")
       terminalEditorCommands[id] = resolvedTerminalEditorCommand(terminalEditorCommand)
       let tab = WorkspaceTab.terminal(id)
       tabs.append(tab)
       activeTab = tab
       saveTabSnapshot()
       Telemetry.shared.track("tab_opened", url: "/tab/editor", title: "Editor Tab",
                              data: ["kind": "terminal-editor"])
   }
   ```
   Uses the shared `terminalCount` counter so ids never collide with regular
   terminals.

5. **`paneContent(for:)`** — the `.terminal(id)` case passes the command:
   ```
   case let .terminal(id):
       SingleTerminalView(
           surfaceID: id,
           workstreamID: workstreamID,
           workingDirectory: workingDirectory,
           command: terminalEditorCommands[id],   // nil for normal terminals
           isFocused: true,
           environmentVars: terminalEnvVars
       )
   ```

6. **Tab labeling** — editor terminals read as an editor, distinguished by
   `terminalEditorCommands[id] != nil`:
   - `tabIcon(_:)` — `.terminal(id)` returns `"doc.text"` when it is an editor
     terminal, else `"terminal"`.
   - `tabLabel(_:)` — `.terminal(id)` returns `"Editor"` (localized) when it is an
     editor terminal, else `nil` (current behavior).

7. **Cleanup** — `closeTab(_:)` removes the map entry:
   `terminalEditorCommands.removeValue(forKey: id)` when a `.terminal(id)` closes.

8. **Command resolution helper** (pure, free function for testability):
   ```
   func resolvedTerminalEditorCommand(_ raw: String) -> String {
       let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
       return trimmed.isEmpty ? "nvim ." : trimmed
   }
   ```

### Settings UI

`Sources/Views/SettingsView.swift`, in the **General** `Section`:

- Add `@AppStorage("dockyard.useTerminalEditor") private var useTerminalEditor: Bool = false`
  and `@AppStorage("dockyard.terminalEditorCommand") private var terminalEditorCommand: String = "nvim ."`.
- A `SettingToggle("Open editor in a terminal", isOn: $useTerminalEditor, description: ...)`.
- When `useTerminalEditor` is true, a `LabeledContent("Editor command")` with a
  `TextField` (`.roundedBorder`, `maxWidth: 200`) bound to `terminalEditorCommand`,
  plus a caption like "Runs in the worktree directory when you open an editor (Cmd+O)."

## Why reuse `.terminal` (not a new tab case or branching inside `.editor`)

- It genuinely is a terminal surface running an editor program.
- A new `WorkspaceTab` case would require edits to ~10 exhaustive `switch`
  statements (`isCloseable`, `RestorableWorkspaceTab.init`, `paneContent`,
  `tabLabel`, `tabIcon`, `tabDragIdentifier`, `reconciled`,
  `startupWorkspaceTabState`, `toggleSplit`, drag reorder) for no behavioral gain.
- Branching inside the `.editor` case would entangle nvim with Monaco's save/dirty
  tracking, file-tree watcher, and the `editorBridge` — none of which apply. It
  would also let the Cmd+S "Save" menu item hijack the keystroke from nvim, since
  `isEditorTabActive` checks for `.editor`. Keeping nvim as a `.terminal` tab avoids
  all of that; nvim saves with `:w`.
- The `terminalEditorCommands` map cleanly identifies editor terminals for
  labeling without any extra flag.

## Edge cases

- **Empty command field:** `resolvedTerminalEditorCommand` falls back to `nvim .`.
- **Toggling the setting at runtime:** affects only newly opened editors. Existing
  tabs (Monaco or nvim) keep rendering as they were opened, because the decision is
  captured at open time (Monaco tabs are `.editor`; nvim tabs are `.terminal` with a
  map entry).
- **Quitting nvim:** surface falls back to a shell (`wait_after_command = true`),
  matching agent/terminal behavior. Closing is via Ctrl+D or Cmd+W.
- **Save shortcuts (Cmd+S / Cmd+Shift+S):** disabled for these tabs because they are
  not `.editor` tabs, so they do not intercept keystrokes intended for nvim.

## Testing

- Unit test `resolvedTerminalEditorCommand`:
  - trims whitespace,
  - falls back to `"nvim ."` on empty/whitespace-only input,
  - returns a custom command unchanged (e.g. `"vim"`, `"hx ."`).
- Manual verification: with the toggle on, Cmd+O opens an nvim tab in the worktree;
  with it off, Cmd+O opens Monaco; the editor tab shows the doc icon + "Editor"
  label; closing the tab removes it cleanly.

## Localization

New user-facing strings added to all five locale files (en, ca, de, es, sv):

- "Open editor in a terminal" (toggle title)
- Toggle description (e.g. "Open your editor in a terminal tab (Cmd+O) instead of
  the built-in editor.")
- "Editor command" (field label)
- Command field caption
- "Editor" (tab label — may already exist; reuse if so)

## Docs

- README: add a short note in the settings/features area describing the toggle.
- The Cmd+O shortcut itself does not change, so the shortcut tables
  (`HelpView.swift`, README shortcut table, website) do not need updates.
