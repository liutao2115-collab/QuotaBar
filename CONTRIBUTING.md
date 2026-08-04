# Contributing

Thanks for improving QuotaBar.

## Local Setup

```sh
swift build
./build-app.sh
```

## Pull Request Checklist

- Keep the menu bar item compact.
- Prefer native macOS controls and system materials.
- Avoid adding network calls unless the privacy impact is explicit.
- Run `swift build` before submitting.

## Design Notes

QuotaBar should stay lightweight: the menu bar shows only the remaining percentage, and the popover should explain the current state without turning into a dashboard.
