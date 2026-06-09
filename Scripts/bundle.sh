#!/bin/zsh
# Build the SwiftPM executable and assemble CommandShiftHero.app.
# Usage: Scripts/bundle.sh [release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
BIN_DIR=".build/arm64-apple-macosx/$CONFIG"
APP="build/CommandShiftHero.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/CommandShiftHero" "$APP/Contents/MacOS/CommandShiftHero"
cp Support/Info.plist "$APP/Contents/Info.plist"

# SwiftPM resource bundle — Bundle.module resolves it next to the executable's
# Resources directory at runtime.
if [ -d "$BIN_DIR/CommandShiftHero_CommandShiftHero.bundle" ]; then
    cp -R "$BIN_DIR/CommandShiftHero_CommandShiftHero.bundle" "$APP/Contents/Resources/"
fi

# Identifier must stay constant across rebuilds or TCC grants are lost.
codesign --force --sign - --identifier com.maxtyroler.CommandShiftHero "$APP"

echo "Bundled: $APP"
