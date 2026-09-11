# Workstream pull request checks

## Purpose

Show CI progress beside each workstream's PR so users can see what needs attention without leaving Dockyard. Preserve the distinction between successful CI and permission to merge.

## Presentation and navigation

- Workspace toolbar, workstream Info, project workstream cards, sidebar workstreams, and the global Open PRs list show a shared checks control for open PRs.
- The compact control uses an icon plus text/counts: pending, failed, passed, cancelled, skipped, no checks, or unavailable. Failure takes priority over pending. Unknown results never appear successful.
- PR numbers and PR-backed lifecycle labels (including review and merged) open that exact PR on GitHub. Manually assigned lifecycle labels without a PR retain their existing meaning.
- Clicking checks opens a popover with individual results and log links, an explicit Open checks on GitHub action, and Refresh. Required checks are identified after fetching details. The popover also reports draft, review, and merge-conflict blockers when available.
- Passing checks are labeled Checks passed, never Ready to merge. GitHub remains authoritative for merge permission and repository rules.
- Merged PRs retain their merged presentation without continuing CI polling.
- Icons and localized text accompany color; counts use tabular digits. Controls support keyboard activation and readable accessibility labels. Card selection must not intercept badge clicks.

## Data and refresh

- Reuse the installed authenticated gh CLI, bounded background process runner, and existing 30-second PR refresh cadence. No additional login or service is introduced.
- Add statusCheckRollup, headRefOid, isDraft, reviewDecision, and mergeStateStatus to the existing repository-level open-PR query. Handle both CheckRun and legacy StatusContext entries.
- Fetch required-check details on demand with gh pr checks --required --json. Accept documented pending/failure exit codes only for this command and require valid JSON. Do not confuse command failure with failed CI.
- Keep the last successful PR snapshot on network/authentication errors. Mark aged check information stale and expose refresh; never interpret a failed list request as an empty PR list or a merge.
- A changed PR head replaces previous check data. Ignore detail responses for an older head; coalesce overlapping refreshes and bind details to repository/PR/head identity.
- Distinguish no checks from missing/malformed check information. Unexpected statuses remain unknown.

## Acceptance criteria

1. Pending, passing, failing, cancelled, skipped, empty, and unknown rollups are classified correctly, including mixed legacy statuses and check runs.
2. Each supported surface displays the same current summary; PR and lifecycle labels navigate to the correct PR.
3. Check details link to the exact reported check URL and identify required checks without claiming full merge readiness.
4. Authentication/network failure preserves the PR and exposes stale/unavailable status. New commits cannot retain green status from the old head.
5. All new copy exists in English, Catalan, German, Spanish, and Swedish, with a What's New entry.
6. Focused model/process tests and the project build/test workflow validate the change. UI verification checks popover layout and independent badge/card interactions.
