# Website demo capture

`./scripts/capture-website-demo.sh` builds Dockyard, launches an isolated demo fixture, drives the canonical product tour with XCTest, records only the Dockyard window with ScreenCaptureKit, and produces the optimized website media in `website/site/media/`.

## Architecture

- `DemoMode` activates only with `--demo-mode` or `DOCKYARD_DEMO_MODE=1`. It creates three fixed workstreams beneath a disposable root and uses a dedicated UserDefaults suite. Normal projects, worktrees, caches, tmux sessions, and preferences are not read or changed.
- `DockyardDemoUITests` drives stable accessibility identifiers through the real sidebar, Info view, run command, embedded browser, Monaco editor, and PR toolbar. Only Coding Agent and GitHub responses are deterministic fixtures; they never invoke an account or remote service.
- `dockyard-demo-recorder` uses ScreenCaptureKit's desktop-independent window filter. It excludes the desktop, menu bar, cursor, audio, and every other application window, and captures the Dockyard window at 2× scale and 30 fps.
- The shell pipeline trims the fixed timeline with `ffmpeg`, encodes H.264/yuv420p MP4 files with `faststart`, creates optimized JPEG posters, and checks each video with `ffprobe`.

Website media is not referenced by `project.yml` and therefore cannot enter the macOS bundle. Optimized MP4/WebP outputs may be committed; `.build/demo-capture/`, raw capture, result bundles, fixture repositories, and logs are ignored.

## One-time setup

Requirements are macOS 14 or newer, a logged-in graphical session, Xcode/XCTest, XcodeGen, built Ghostty resources, `ffmpeg`/`ffprobe`, and the existing Monaco build prerequisites.

1. Build once or run the command below. macOS may prompt for privacy access.
2. In **System Settings → Privacy & Security → Screen Recording**, enable the terminal application running the script.
XCTest supplies the UI automation channel, so this workflow does not require a separate Accessibility grant. Quit and reopen the terminal after changing Screen Recording permission.

The script only checks these controls; it never attempts to bypass or grant them. If a check fails, it prints the exact missing permission and exits before launching the tour.

## Regenerate everything

From the repository root:

```bash
./scripts/capture-website-demo.sh
```

The outputs are:

- `dockyard-tour.mp4` and `dockyard-tour.jpg`
- `workstreams.mp4` and `workstreams.jpg`
- `coding-agent.mp4` and `coding-agent.jpg`
- `live-preview.mp4` and `live-preview.jpg`
- `editor-and-pr.mp4` and `editor-and-pr.jpg`

The script traps success, failure, and interruption. It terminates the recorder and demo app and removes the disposable fixture in every case.

## Updating the tour

Change UI actions and pacing in `Tests/DockyardDemoUITests/DockyardDemoUITests.swift`. Update fixed data, files, agent messages, or mock PR state in `Sources/Models/DemoMode.swift`. Accessibility queries should remain semantic; do not introduce coordinates when a control can expose an identifier.

Clip timing and the stable camera framing are defined in `scripts/capture-website-demo.sh`. Keep the full window capture sharp unless a predetermined crop clearly improves comprehension. If actions move in the timeline, update clip start/duration values together with the UI test.

## Verification

Inspect codec, dimensions, rate, and duration with:

```bash
ffprobe -v error -show_streams -show_format website/site/media/dockyard-tour.mp4
```

Build and check the website container with:

```bash
docker build -t dockyard-website website
docker run --rm -p 8080:8080 dockyard-website
curl -f http://127.0.0.1:8080/
curl -f http://127.0.0.1:8080/ca/
curl -f http://127.0.0.1:8080/healthz
```

Before publishing, watch the full tour and each clip. Confirm the frame contains only Dockyard fixture names (`Dockyard`, `check-short-inode`, `sidebar-polish`, `release-notes`), no notification banners, personal directories, usernames, tokens, other windows, or unexpected browser content. The recorder's window-only filter prevents ambient desktop capture, but visual review remains the final privacy check.

## Troubleshooting

- **Permission error:** grant the single named privacy control, quit/reopen the terminal or Xcode, then rerun the same command.
- **Ghostty resources missing:** build the pinned submodule artifacts as described in `AGENTS.md`; do not modify the submodule.
- **Window timeout:** ensure the active macOS session is unlocked and no previous UI-test Dockyard process is running.
- **Port 4317 is busy:** stop the conflicting local process. The fixture intentionally uses a fixed port so the recording is deterministic.
- **A clip boundary is wrong:** review `.build/demo-capture/dockyard-tour-raw.mp4`, adjust the four fixed trim ranges, and rerun.
- **Media fails on the site:** posters and captions preserve the page layout and explanation. Verify filenames and the nginx `/media/` response before recapturing.
