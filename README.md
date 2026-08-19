# QuotaBar

QuotaBar is a small native macOS menu bar utility that shows your remaining weekly ChatGPT/Codex usage as a simple percentage.

It is designed to feel quiet and native: just a compact number in the menu bar, with a lightweight popover for the current week, reset time, manual calibration, notifications, and launch-at-login.

## Features

- Menu bar percentage for remaining weekly usage
- Native SwiftUI/AppKit popover with a compact Apple-style layout
- Background auto-refresh while the menu bar app is running
- Near-real-time local updates when Codex session metadata changes
- Manual fallback when no recent usage data is available
- Low-usage notification threshold
- Launch-at-login toggle
- No network upload and no conversation content parsing

## Privacy

QuotaBar reads recent local files under:

```text
~/.codex/sessions
```

It only looks for `payload.rate_limits` usage metadata in Codex session JSONL files. It does not upload data, does not call a server, and does not intentionally read or display conversation text.

## Requirements

- macOS 14 or later
- Swift 6 toolchain or newer

## Build

From the project directory:

```sh
./build-app.sh
```

The script builds a release binary, assembles `QuotaBar.app`, and applies local ad-hoc signing so the app can run on your Mac.

## Run

After building, open:

```sh
open QuotaBar.app
```

The menu bar item shows the remaining percentage. Click it to open the compact usage popover.

On first launch, macOS may ask you to allow the app from Privacy & Security settings because the app is locally signed.

## How It Works

Codex records rate-limit metadata in local session files. QuotaBar watches the local sessions folder, refreshes when usage metadata changes, and also performs a quiet background refresh every 30 seconds as a fallback. It scans recent session files, selects the weekly window, and displays:

- remaining percentage
- used percentage
- next reset time
- last updated time

When the weekly reset has passed, the app projects the new week as 100% remaining until fresh usage data is observed.

## Repository Layout

```text
Sources/QuotaBar/
  QuotaBarApp.swift        macOS menu bar host
  QuotaMenuView.swift      popover UI
  UsageStore.swift         app state, refresh, notifications, login item
  SessionUsageReader.swift local usage metadata reader
  SessionUsageWatcher.swift local session file change watcher
  UsageSnapshot.swift      usage model
build-app.sh               release build and app bundle script
Package.swift              Swift package manifest
```

## Roadmap

- Optional signed release builds
- App icon and DMG packaging
- More explicit diagnostics when no usage metadata is found

## License

MIT
