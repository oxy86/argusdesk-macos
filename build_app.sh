#!/bin/zsh
# build_app.sh — Build a production ArgusDesk.app bundle from SwiftPM sources.
#
# Usage:
#   ./build_app.sh              — builds Debug app to build/ArgusDesk.app
#   ./build_app.sh release      — builds Release app to build/ArgusDesk.app
#   ./build_app.sh release universal — builds for Apple silicon and Intel
#   ./build_app.sh release universal build/release/ArgusDesk.app
#                               — keeps the running development app untouched
#   ./build_app.sh zip          — builds and zips into build/ArgusDesk.zip

set -euo pipefail

cd "$(dirname "$0")"

# --- Determine build config ---
CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|Debug)
    SWIFT_FLAGS=()
    ;;
  release|Release)
    SWIFT_FLAGS=(--configuration release)
    ;;
  zip)
    CONFIG="debug"
    SWIFT_FLAGS=()
    DO_ZIP=true
    ;;
  *)
    echo "Usage: $0 [debug|release|zip] [native|universal] [build/path/ArgusDesk.app]"
    exit 1
    ;;
esac

# --- Build with SwiftPM ---
# Explicit triples keep each architecture's output separate. The same macOS
# deployment target is used for both slices of a universal distribution.
ARCHITECTURE="${2:-native}"
BINARIES=()
case "$ARCHITECTURE" in
  native)
    swift build "${SWIFT_FLAGS[@]}"
    BINARY_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
    BINARIES=("$BINARY_DIR/ArgusDesk")
    ;;
  universal)
    for ARCH in arm64 x86_64; do
      TRIPLE="$ARCH-apple-macosx14.0"
      swift build "${SWIFT_FLAGS[@]}" --triple "$TRIPLE"
      BINARY_DIR="$(swift build "${SWIFT_FLAGS[@]}" --triple "$TRIPLE" --show-bin-path)"
      BINARIES+=("$BINARY_DIR/ArgusDesk")
    done
    ;;
  *)
    echo "Architecture must be native or universal."
    exit 1
    ;;
esac

# --- Prepare app bundle directory ---
APP_DIR="${3:-build/ArgusDesk.app}"
# Generated bundles stay beneath build/, including when packaging separately
# from the development app. Never recursively remove an arbitrary input path.
if [[ "$APP_DIR" != build/* || "$APP_DIR" != */ArgusDesk.app || "$APP_DIR" == *"/../"* ]]; then
  echo "Output must be a path beneath build/ ending in /ArgusDesk.app."
  exit 1
fi
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# --- Copy the binary ---
if [ "${#BINARIES[@]}" -gt 1 ]; then
  xcrun lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/ArgusDesk"
else
  cp "${BINARIES[1]}" "$APP_DIR/Contents/MacOS/ArgusDesk"
fi
chmod +x "$APP_DIR/Contents/MacOS/ArgusDesk"

# --- Copy Info.plist ---
cp Info.plist "$APP_DIR/Contents/Info.plist"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE.txt"

# --- Copy icons from Assets/ ---
ASSETS_DIR="Assets"
echo "=== Copying icons ==="
if [ -f "$ASSETS_DIR/Icon.icns" ]; then
  cp "$ASSETS_DIR/Icon.icns" "$APP_DIR/Contents/Resources/Icon.icns"
  echo "  App icon: Icon.icns"
else
  echo "  Warning: $ASSETS_DIR/Icon.icns not found"
fi

if [ -f "$ASSETS_DIR/menubar-icon.png" ]; then
  cp "$ASSETS_DIR/menubar-icon.png" "$APP_DIR/Contents/Resources/menubar-icon.png"
  echo "  Menu bar icon: menubar-icon.png (22x22)"
else
  echo "  Warning: $ASSETS_DIR/menubar-icon.png not found"
fi

if [ -f "$ASSETS_DIR/menubar-icon@2x.png" ]; then
  cp "$ASSETS_DIR/menubar-icon@2x.png" "$APP_DIR/Contents/Resources/menubar-icon@2x.png"
  echo "  Menu bar icon (retina): menubar-icon@2x.png (44x44)"
else
  echo "  Warning: $ASSETS_DIR/menubar-icon@2x.png not found"
fi

# --- Code-sign in development mode ---
echo "=== Code-signing ==="
codesign --force --deep --sign - --identifier gr.webzein.ArgusDesk "$APP_DIR"

# --- Create zip if requested ---
if [ "${DO_ZIP:-false}" = "true" ]; then
  echo "=== Zipping ==="
  cd build
  zip -r "ArgusDesk.zip" "ArgusDesk.app" -x "*/.DS_Store"
  cd ..
  echo "Zip: build/ArgusDesk.zip"
fi

echo ""
echo "=== Done ==="
echo "App bundle: $APP_DIR"
echo "Launch: open \"$APP_DIR\""
