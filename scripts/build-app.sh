#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Foldwake.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
LAUNCH_DAEMONS_DIR="$CONTENTS_DIR/Library/LaunchDaemons"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUNDLE_ID="io.github.thavguard.foldwake"
HELPER_ID="$BUNDLE_ID.helper"
HELPER_PLIST="$HELPER_ID.plist"

cd "$ROOT_DIR"
if [[ -f "$HOME/.swiftly/env.sh" ]]; then
  # Use the current Swift.org toolchain when Swiftly is installed.
  # shellcheck disable=SC1091
  source "$HOME/.swiftly/env.sh"
  export PATH="$HOME/.swiftly/bin:$PATH"
  hash -r
fi

swift --version
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$LAUNCH_DAEMONS_DIR" "$RESOURCES_DIR"
cp ".build/release/Foldwake" "$MACOS_DIR/Foldwake"
cp ".build/release/FoldwakeHelper" "$MACOS_DIR/FoldwakeHelper"
cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

SIGN_IDENTITY="${FOLDWAKE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  printf 'error: no signing identity found. Set FOLDWAKE_SIGN_IDENTITY to an Apple Development or Developer ID Application identity.\\n' >&2
  exit 1
fi
if [[ "$SIGN_IDENTITY" == "-" && "${FOLDWAKE_ALLOW_AD_HOC:-}" != "1" ]]; then
  printf 'error: ad-hoc signing is disabled. Set FOLDWAKE_ALLOW_AD_HOC=1 only for non-runtime CI packaging checks.\\n' >&2
  exit 1
fi

codesign --force --options runtime --identifier "$HELPER_ID" --sign "$SIGN_IDENTITY" "$MACOS_DIR/FoldwakeHelper" >/dev/null
HELPER_CDHASH="$(codesign -dv --verbose=4 "$MACOS_DIR/FoldwakeHelper" 2>&1 | sed -n 's/^CDHash=//p' | head -1)"
HELPER_CDHASH_B64="$(printf '%s' "$HELPER_CDHASH" | xxd -r -p | base64)"

cat > "$LAUNCH_DAEMONS_DIR/$HELPER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_ID</string>
  <key>BundleProgram</key>
  <string>Contents/MacOS/FoldwakeHelper</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_ID</key>
    <true/>
  </dict>
  <key>SpawnConstraint</key>
  <dict>
    <key>cdhash</key>
    <data>$HELPER_CDHASH_B64</data>
  </dict>
</dict>
</plist>
PLIST

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Foldwake</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.thavguard.foldwake</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleName</key>
  <string>Foldwake</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
echo "$APP_DIR"
