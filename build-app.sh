#!/bin/sh
set -eu
cd "$(dirname "$0")"
CACHE="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/timetracker-swift-cache}"
mkdir -p "$CACHE"
export CLANG_MODULE_CACHE_PATH="$CACHE" SWIFTPM_MODULECACHE_OVERRIDE="$CACHE"
APP="$PWD/Time Tracker.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/time-tracker-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

build_executable() {
    swift build -c release --disable-sandbox "$@" >&2
    swift build -c release --disable-sandbox "$@" --show-bin-path
}

case "${1:-}" in
    "") BIN="$(build_executable)/TimeTracker" ;;
    --universal)
        ARM_BIN="$(build_executable --triple arm64-apple-macosx14.0)/TimeTracker"
        INTEL_BIN="$(build_executable --triple x86_64-apple-macosx14.0)/TimeTracker"
        BIN="$STAGING_DIR/TimeTracker"
        lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$BIN"
        ;;
    *) printf 'Usage: %s [--universal]\n' "$0" >&2; exit 2 ;;
esac
swift scripts/RenderAppIcon.swift "$STAGING_DIR/AppIcon.icns"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
STAGED_BIN="$(mktemp "$APP/Contents/MacOS/.TimeTracker.XXXXXX")"
trap 'rm -f "$STAGED_BIN"; rm -rf "$STAGING_DIR"' EXIT
cp -p "$BIN" "$STAGED_BIN"
mv -f "$STAGED_BIN" "$APP/Contents/MacOS/TimeTracker"
cp "$STAGING_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TimeTracker</string>
<key>CFBundleIdentifier</key><string>local.bekheet.timetracker</string>
<key>CFBundleName</key><string>Time Tracker</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>2.0</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
touch "$APP"
printf 'Built: %s\n' "$APP"
