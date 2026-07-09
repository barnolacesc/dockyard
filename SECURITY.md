# Security Policy

## Reporting a Vulnerability

Please report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/barnolacesc/dockyard/security/advisories/new).
Do not open a public issue for security problems.

You can expect an acknowledgement within a few days. Fixes are released as a
patch version as soon as they are ready; there is no fixed embargo period, but
coordinated disclosure is appreciated.

## Supported Versions

Only the latest release receives security fixes. Dockyard follows semantic
versioning via release-please; updating is low-risk within a major version.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ (update to latest) |

## Scope

Dockyard is a local developer tool. Reports we consider in scope include:

- Command or argument injection through project names, branch names, file
  paths, or config files (`.dockyard.json` and its fallbacks)
- Execution of repo-provided scripts without the user's approval
- Update-mechanism integrity issues (Sparkle feed, self-update flow)
- Leakage of local data to the network

Out of scope: issues requiring an already-compromised local account, and the
inherent capabilities of tools the user chooses to run inside terminals
(shells, coding agents, dev servers).

## Hardening Highlights

- No telemetry and no crash reporting; see [PRIVACY.md](PRIVACY.md)
- Repo-provided scripts require one-time user approval and re-approval on change
- Minimal entitlements; see [THREAT_MODEL.md](THREAT_MODEL.md)
- Release DMGs are Developer ID-signed, notarized, and Sparkle updates are
  EdDSA-signed with a key pinned in the app
