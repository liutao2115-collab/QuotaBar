# Publishing an update

QuotaBar is an existing repository. Update its source first, then publish a release from that updated commit. Do not recreate the repository or replace an older release.

## Source update

1. Review the local changes and build the app.
2. Push the prepared commit, or use GitHub's **Add file → Upload files** to upload the prepared source-update contents to the existing repository. Preserve `Sources/QuotaBar/` and `Tests/` paths; do not upload an enclosing source-update folder.
3. Confirm the default branch contains the new five-hour menu bar behavior and `CHANGELOG.md` entry before creating the release tag.

Do not upload `.git`, `.build`, local Codex session data, or credentials. App binaries belong in Release assets rather than the source tree.

## Release

1. Verify the latest published version and the availability of the proposed new tag.
2. Create the new tag on the updated source commit.
3. Set the release title to `QuotaBar v<version>` and paste the prepared release notes.
4. Attach the app ZIP and `SHA256SUMS.txt`; never reuse an archive built before the latest changes.
5. Verify the published tag, source version, download filename, and checksum agree.

The app is locally ad-hoc signed, not Developer ID signed or notarized. Identify the supported CPU architecture in the download filename. GUI checks on the target Mac are required before calling a release fully verified.

## Repository description

Native macOS menu bar utility showing five-hour remaining Codex usage, with five-hour and weekly quotas side by side.

Suggested topics: `macos`, `swift`, `swiftui`, `menubar`, `codex`, `productivity`.
