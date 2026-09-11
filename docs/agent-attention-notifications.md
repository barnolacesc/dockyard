# Agent Attention Notifications

Design specification for notifying the user when a Coding Agent needs input and
deep-linking the notification back to the relevant workstream.

## Problem

Dockyard already records Coding Agent state transitions in the Attention inbox,
but a user working in another app may not see that an agent is waiting. Existing
terminal-bell notifications are indirect, have no workstream destination, and do
not handle notification clicks.

The unread badge also uses white text on `systemYellow`. At its compact size,
especially in the collapsed sidebar, the number has insufficient visual contrast.

## Goals

- Notify when a Coding Agent transitions to `waiting`
- Identify the project and workstream without exposing transcript content
- Open Dockyard, select the workstream, and focus its Coding Agent when clicked
- Avoid notifications when the user is already looking at that Coding Agent
- Avoid duplicate notifications for the same state transition
- Make unread counts legible in both sidebar modes and appearances

## Non-goals

- Notify for every completed or inactive agent turn
- Include the agent's question or terminal contents in the notification
- Replace the in-app Attention inbox
- Redesign the full sidebar or application visual system
- Add notification actions such as replying from Notification Center

## Notification behavior

### Trigger

Send one system notification for each new `AgentActivityEvent` whose kind is
`.waiting`. The activity event, rather than terminal bell output, is the canonical
trigger so repeated filesystem refreshes and terminal escape sequences do not
create duplicates.

Do not notify for `.started`, `.completed`, or `.inactive`. Those events continue
to appear in the Attention inbox. A future preference may opt completed turns in,
but it is not part of this feature.

### Presentation

- Title: project name
- Body: localized `Coding Agent needs your attention in “%@”.`, interpolated
  with the workstream name
- Sound: the existing bundled `notification.wav`
- Identifier: `agent-attention.<event UUID>`
- Metadata in `UNMutableNotificationContent.userInfo`:
  - `kind`: `agent-attention`
  - `workstreamID`: lowercased UUID string
  - `eventID`: lowercased UUID string

No prompt, response, command, path, branch, or transcript content is included.

### Suppression

Suppress the banner and sound only when all of the following are true:

- Dockyard is active
- The relevant workstream is selected
- Its Coding Agent tab is selected

Still retain the Attention event. If Dockyard is active on a different project,
workstream, tab, settings screen, or Attention screen, deliver the notification.

### Click destination

On the default notification action:

1. Validate `kind`, `workstreamID`, and `eventID` from the payload.
2. Activate Dockyard and bring its main window forward.
3. Resolve the workstream from the current `ProjectList`.
4. Select `.workstream(workstreamID)`.
5. After the workstream detail is mounted, post the existing `.focusAgent`
   notification so the Coding Agent tab is selected and focused.
6. Mark the matching activity event as read.

If the project or workstream no longer exists, activate Dockyard, open Attention,
and leave the event readable there. Invalid or unrelated notification payloads
must not change navigation.

## Proposed structure

### `AgentAttentionNotifier`

Add a small `@MainActor` service that observes newly inserted activity events,
resolves their project/workstream context, applies foreground suppression, and
submits `UNNotificationRequest`s. Inject the notification center and foreground
context in tests.

Keep notification creation out of `AgentActivityStore`: that store remains the
persistence and transition layer and stays usable without system side effects.

### Navigation event

Add an internal `Notification.Name.openAgentAttention` carrying UUID values as
strings or a small validated payload type. `AppDelegate` translates the system
notification response into this event; `ContentView` owns the actual selection
because it owns `ProjectList` and `SidebarSelection`.

The navigation route must work whether Dockyard is active, hidden, or behind
another app. It must not create a second window.

### Existing terminal notifications

Keep generic terminal desktop notifications intact. Stop treating a terminal bell
as the primary agent-attention signal; otherwise a waiting transition and its bell
may produce two banners. If the bell can be identified as coming from the Coding
Agent surface, suppress that bell notification when the workstream is already in
`.waiting`; unrelated terminal bells remain unchanged.

## Unread badge contrast

The badge is a semantic count component, not raw `statusWarning` styling. Extract
or introduce an `UnreadCountBadge` used by:

- `SidebarRail`
- `SidebarAttentionRow`
- `AttentionView` header
- The collapsed update badge if it keeps the same visual treatment

Use an appearance-aware foreground/background pair with measured contrast of at
least 4.5:1 for the small numeral. The preferred direction is dark text on the
existing yellow warning fill; it preserves the attention meaning while fixing the
contrast. If the final system-yellow variants cannot guarantee the target across
appearances, use explicit semantic badge colors in `DesignColor` instead of
changing `statusWarning` globally.

Keep `.tabularNumbers()`, the bold rounded numeral, capsule shape, and current hit
areas. Verify two- and three-digit counts at 1x and 2x display scales. This focused
fix should ship independently of a future sidebar redesign.

## Localization

Add every new user-facing string to English, Catalan, German, Spanish, and Swedish.
The workstream name must be inserted with a localized format string rather than by
concatenating translated fragments.

## Tests

- A transition to `.waiting` submits exactly one request with the expected payload
- Re-observing the same state/event does not submit another request
- Other activity kinds do not submit requests
- The exact active workstream and Agent tab suppress the request
- A different workstream or tab does not suppress it
- Valid response payload selects the workstream, focuses Agent, and marks read
- A removed workstream falls back to Attention without crashing
- Malformed or unrelated payloads do not navigate
- Badge foreground/background variants meet the contrast threshold
- Notification strings exist in all five locale files

## Acceptance criteria

- Leaving Dockyard while an agent works produces one system notification when it
  asks for input
- Clicking that notification brings the existing Dockyard window forward at the
  correct workstream's Coding Agent tab
- No transcript content is exposed in Notification Center
- Watching that same Coding Agent does not produce a redundant banner or sound
- The unread count is clearly legible in collapsed and expanded sidebars in light
  and dark appearances

## Follow-up

A later notification preference can offer `Needs input only`, `Needs input and
completed turns`, and `Off`. It is deliberately deferred until the core behavior
has been validated.
