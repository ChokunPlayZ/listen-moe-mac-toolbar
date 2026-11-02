#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/build/LISTEN.moe.app"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ListenMoe" "$APP/Contents/MacOS/ListenMoe"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/build"
iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP"
printf '\nBuilt %s\nOpen with: open "%s"\n' "$APP" "$APP"
