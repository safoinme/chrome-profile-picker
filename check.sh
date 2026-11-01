#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcrun swift-format lint --strict Sources/*.swift Tests/*.swift
bash -n build.sh check.sh package.sh
plutil -lint Info.plist
mkdir -p build/tests
xcrun swiftc -swift-version 6 -warnings-as-errors \
  -module-cache-path "${TMPDIR:-/tmp}/chrome-profile-picker-module-cache" \
  Sources/ProfileStore.swift Sources/LinkRouting.swift Tests/main.swift -o build/tests/behavior
build/tests/behavior
./build.sh
echo 'CHECK OK: Swift format, shell syntax, plist, behavior tests, universal build, signature'
