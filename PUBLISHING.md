# Publishing

This file records the release flow for QuotaBar.

## First GitHub Upload

1. Create a GitHub repository named `QuotaBar`.
2. Keep the repository private first if you want to review the project before making it public.
3. Add the remote:

```sh
git remote add origin git@github.com:<owner>/QuotaBar.git
```

or, for HTTPS:

```sh
git remote add origin https://github.com/<owner>/QuotaBar.git
```

4. Push the first commit:

```sh
git push -u origin main
```

## Release Checklist

- Run `swift build -c release`.
- Run `./build-app.sh`.
- Confirm `QuotaBar.app` launches locally.
- Create a GitHub release tag, for example `v1.0.0`.
- Attach a signed or locally built app archive only if you want downloadable binaries.

## Suggested Repository Description

Native macOS menu bar utility for showing remaining weekly ChatGPT/Codex usage.

## Suggested Topics

```text
macos
swift
swiftui
menubar
chatgpt
codex
productivity
```
