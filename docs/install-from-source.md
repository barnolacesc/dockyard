# Installing Dockyard from Source

The recommended path for corporate machines where DMG installs are
restricted: you clone the public repository, build locally, and every update
is a visible `git pull` + rebuild. The chain of custody is your git remote
plus your own toolchain — no downloaded binaries involved (the app you run is
signed by your local build, not distributed).

## Prerequisites

| Tool | Used for | Install |
| --- | --- | --- |
| Xcode 16+ (macOS 14+) | Building the app | App Store / developer.apple.com |
| XcodeGen | Generating the Xcode project from `project.yml` | `brew install xcodegen` |
| Zig (version noted in `ghostty/build.zig.zon`) | Building the Ghostty terminal engine | `brew install zig` |
| Bun | Building the Monaco editor bundle | `brew install oven-sh/bun/bun` |

## Build and install

```bash
git clone --recurse-submodules https://github.com/barnolacesc/dockyard.git
cd dockyard

# Build the Ghostty terminal engine (once per submodule update)
cd ghostty && zig build && cd ..

# Build a release configuration, copy Dockyard.app into /Applications, and launch it
./scripts/dev.sh install
```

`dev.sh` handles `xcodegen generate` and building the Monaco editor bundle
automatically.

## Updates

Dockyard detects that it was built from a source checkout and periodically
runs `git fetch` against *your* clone's remote. When new commits exist on
`main`, the sidebar shows an update button; clicking it opens Terminal.app
and visibly runs `scripts/self-update.sh`, which does `git merge --ff-only
origin/main` and rebuilds into /Applications. Nothing updates silently.

To update manually instead:

```bash
git pull --ff-only
./scripts/dev.sh install
```

## What a security review should know

- Source installs never contact the Sparkle appcast; the only network
  activity the app initiates is the `git fetch` described above.
  See [PRIVACY.md](../PRIVACY.md).
- No telemetry or crash reporting exists in the codebase.
- Repo-provided scripts require explicit user approval before running;
  see [THREAT_MODEL.md](../THREAT_MODEL.md).
- Review the release entitlements at `Resources/dy.entitlements` — three
  entries, each commented with its justification.
