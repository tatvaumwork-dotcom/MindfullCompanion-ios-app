#!/bin/sh
# Re-renders AppIcon.png and LaunchLogo*.png from the logo geometry in TatvaumLogo.swift.
set -e
cd "$(dirname "$0")/.."
out=$(mktemp -d)
cp Scripts/render-logo.swift "$out/main.swift"   # top-level code must live in main.swift
xcrun swiftc -swift-version 5 -o "$out/render-logo" TatvaumConnect/UI/Splash/TatvaumLogo.swift "$out/main.swift"
"$out/render-logo" TatvaumConnect/Resources/Assets.xcassets
rm -rf "$out"
