#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
APP_NAME="FastNativeDownloadManager"
BUNDLE_NAME="Fast Native Download Manager"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"

usage() {
  echo "usage: ./build.sh [build|--run|--verify|--clean|--extension]" >&2
}

cd "$ROOT_DIR"

build_app() {
  swift build
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/Packaging/FastNativeDownloadManager-Info.plist" "$APP_CONTENTS/Info.plist"
  if [[ -f "$ROOT_DIR/Packaging/FastNativeDownloadManager.icns" ]]; then
    cp "$ROOT_DIR/Packaging/FastNativeDownloadManager.icns" "$APP_RESOURCES/FastNativeDownloadManager.icns"
  fi
  echo "Built: $APP_BUNDLE"
}

package_extensions() {
  mkdir -p "$DIST_DIR"
  local chrome_version firefox_version
  chrome_version="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT_DIR/Browser Extension/chrome/manifest.json" | head -n 1)"
  firefox_version="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT_DIR/Browser Extension/firefox/manifest.json" | head -n 1)"

  (
    cd "$ROOT_DIR/Browser Extension/chrome"
    zip -qr "$DIST_DIR/fast-native-download-manager-chrome-$chrome_version.zip" . -x 'native-host/*' '*.DS_Store'
  )
  (
    cd "$ROOT_DIR/Browser Extension/firefox"
    zip -qr "$DIST_DIR/fast-native-download-manager-firefox-$firefox_version.zip" . -x '*.DS_Store'
  )
  echo "Packaged browser extensions in: $DIST_DIR"
}

case "$MODE" in
  build)
    build_app
    ;;
  --run|run)
    "$ROOT_DIR/script/build_and_run.sh" run
    ;;
  --verify|verify)
    "$ROOT_DIR/script/build_and_run.sh" --verify
    ;;
  --clean|clean)
    swift package clean
    rm -rf "$APP_BUNDLE"
    echo "Cleaned build artifacts."
    ;;
  --extension|extension|--extensions|extensions)
    package_extensions
    ;;
  *)
    usage
    exit 2
    ;;
esac
