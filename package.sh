#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
mkdir -p dist
stage=$(mktemp -d "${TMPDIR:-/tmp}/profile-picker-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "build/Profile Picker.app" "$stage/Profile Picker.app"
ln -s /Applications "$stage/Applications"
cp INSTALL.txt "$stage/Read Me.txt"
image="dist/Profile-Picker-$version.dmg"
hdiutil create -volname 'Profile Picker' -srcfolder "$stage" \
  -format UDZO -ov "$image"
hdiutil verify "$image"
shasum -a 256 "$image" > "$image.sha256"
echo "PACKAGE OK: $image"
