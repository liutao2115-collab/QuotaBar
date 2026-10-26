# QuotaBar

QuotaBar is a small native macOS menu bar utility that shows your remaining five-hour Codex usage as a simple percentage, with both five-hour and weekly quotas in its popover.

It is designed to feel quiet and native: a compact menu bar number and two side-by-side quota columns with their reset times. Manual calibration, notifications, and launch-at-login are available from the settings menu.

## Features

- Menu bar percentage for remaining five-hour usage
- Native SwiftUI/AppKit popover with a compact Apple-style layout
- Background auto-refresh while the menu bar app is running
- Active official quota queries through the installed Codex client's documented app-server interface
- Near-real-time local updates when Codex session metadata changes
- Reads long-running Codex sessions by file modification time, so stale directory dates do not hide fresh usage data
- Shows five-hour and weekly remaining percentages side by side, with separate reset times
- Shows the data source and capture time, and marks old data as awaiting an update
- Shows a pending state instead of guessing a new percentage after a weekly or five-hour reset
- Manual fallback when no recent usage data is available
- Low-usage notifications for the five-hour quota
- Launch-at-login toggle
- No conversation upload or conversation content parsing

## Privacy

QuotaBar reads recent local files under:

```text
~/.codex/sessions
```

For active queries, QuotaBar uses the installed Codex client's documented `account/rateLimits/read` interface. The client handles its own existing login and makes authenticated requests to OpenAI. QuotaBar does not read, copy, or log authentication tokens, and never starts an AI conversation or consumes a reset credit.

Local fallback only looks for `payload.rate_limits` metadata in session JSONL files. QuotaBar does not upload session files or intentionally parse or display conversation text. Its separate client runtime state is stored under `~/Library/Application Support/QuotaBar/CodexRuntime`.

## Requirements

- macOS 14 or later
- The downloadable app archive is built for Apple Silicon (arm64). Intel Macs have not been verified.
- Building from source requires Swift 6 or newer.
- Active refresh requires an installed Codex app or CLI with a supported app-server interface and an existing ChatGPT login. Without it, local session records and manual calibration remain available.

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

Click outside the popover, press Escape, or click the menu bar percentage again to close it. The popover has no automatic dismissal timeout, so it stays open while you read or edit settings.

On first launch, macOS may ask you to allow the app from Privacy & Security settings because the app is locally signed.

## How It Works

QuotaBar queries official account limits on startup, when the popover opens, and on manual refresh. While running, it normally queries at most once per minute; a missing or expired five-hour window allows retries after 15 seconds. The local timer checks every 30 seconds, so retries happen at the next timer or file-change event. Requests have a bounded timeout and reuse a single background client process.

The local sessions folder watcher is retained as a fallback. QuotaBar prefers official results; if querying is unavailable, it keeps the newer of the local record and its previous snapshot. Session files are not rescanned while official data is available. Each window is identified by duration. The app displays:

- five-hour remaining percentage in the menu bar
- five-hour and weekly remaining percentages in the popover
- each quota's next reset time
- last updated time

After a reset, QuotaBar actively requests new account limits. If that request is unavailable, expired values remain pending rather than being guessed as 100%. A successful official query updates the capture time; rereading an old local record does not.

Each window expires independently. Missing or expired five-hour data displays as `--%` in the menu bar and is never replaced by the weekly percentage.

## Repository Layout

```text
Sources/QuotaBar/
  QuotaBarApp.swift        macOS menu bar host
  QuotaMenuView.swift      popover UI
  UsageStore.swift         app state, refresh, notifications, login item
  CodexUsageClient.swift   official rate-limit RPC client and response parser
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

## Official protocol reference

[Codex App Server — rate limits](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)
