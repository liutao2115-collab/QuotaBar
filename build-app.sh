#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
cd "$project_dir"

swift build -c release

app_dir="$project_dir/QuotaBar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/QuotaBar" "$app_dir/Contents/MacOS/QuotaBar"

plutil -create xml1 "$app_dir/Contents/Info.plist"
plutil -insert CFBundleExecutable -string QuotaBar "$app_dir/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.quotabar "$app_dir/Contents/Info.plist"
plutil -insert CFBundleName -string QuotaBar "$app_dir/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string QuotaBar "$app_dir/Contents/Info.plist"
plutil -insert CFBundleVersion -string 1 "$app_dir/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0.0 "$app_dir/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$app_dir/Contents/Info.plist"
plutil -insert LSUIElement -bool true "$app_dir/Contents/Info.plist"
plutil -insert NSHumanReadableCopyright -string "Personal utility" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
