# Changelog

## Unreleased

## 1.0.2

- Added active official quota refresh through the installed Codex client, so the display no longer depends solely on new session-log entries after a reset.
- Added bounded query timeouts, cached background polling, reconnect handling, and local-record fallback when the client or login is unavailable.
- Fixed stale usage readings when Codex writes new rate-limit metadata into a long-running session file stored under an older date folder.
- Added a separate five-hour remaining quota row in the popover when that window is available.
- Added a lightweight stale-data hint when the latest captured usage metadata is older than 30 minutes.
- Stopped projecting 100% remaining after a reset; weekly and five-hour values now wait for fresh Codex data.
- Labeled the popover's data source and capture time more clearly.
- Switched the menu bar percentage to the five-hour remaining quota.
- Replaced the stacked popover with compact side-by-side five-hour and weekly columns, each with its own reset time; removed the progress bar and used-percentage metric.
- Kept missing and expired quota windows independent, without substituting weekly data for five-hour data.
- Updated manual calibration and low-usage notifications to support the five-hour focus.
- Improved native popover dismissal with outside clicks, Escape, and app switching; kept the popover open while viewing or editing without a timeout.
- Formatted reset dates explicitly in Chinese, such as `10月30日 11:59`.

## 1.0.1

- Moved automatic refresh into the background store so the menu bar percentage updates even when the popover is closed.
- Added local session-folder watching for faster updates after Codex writes new usage metadata.
- Kept a 30-second background refresh fallback for reliability.

## 1.0.0

- Added native macOS menu bar percentage display.
- Added compact weekly usage popover.
- Added local Codex usage metadata reader.
- Added manual calibration fallback.
- Added low-usage notifications.
- Added launch-at-login support.
