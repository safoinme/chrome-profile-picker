#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Chrome Profile Picker.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/bin
cp Info.plist "$app/Contents/Info.plist"
cp Assets/*.svg "$app/Contents/Resources/"
cp THIRD_PARTY_NOTICES.txt "$app/Contents/Resources/"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 6 -warnings-as-errors -O -target "$arch-apple-macosx13.0" \
    -module-cache-path "${TMPDIR:-/tmp}/chrome-profile-picker-module-cache" \
    Sources/*.swift -o "build/bin/ChromeProfilePicker-$arch"
done
lipo -create build/bin/ChromeProfilePicker-arm64 build/bin/ChromeProfilePicker-x86_64 \
  -output "$app/Contents/MacOS/ChromeProfilePicker"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo 'BUILD OK: build/Chrome Profile Picker.app (Apple silicon + Intel, macOS 13+)'
