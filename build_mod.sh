#!/usr/bin/env bash
# Baut die modifizierte DynamicNotch-Version und ersetzt /Applications/DynamicNotch.app.
# Braucht das komplette Xcode (nicht nur die Command Line Tools).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/DynamicNotchModDerivedData}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/DynamicNotch.app"
TARGET_PATH="/Applications/DynamicNotch.app"
SOURCES_DIR="$ROOT_DIR/DynamicNotch/Resources/MediaSources"

echo "Baue DynamicNotch (Release) …"
xcodebuild \
  -project "$ROOT_DIR/DynamicNotch.xcodeproj" \
  -scheme DynamicNotch \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build | grep -E "error:|warning: .*Claude|warning: .*MediaSource|BUILD" || true

[[ -d "$APP_PATH" ]] || { echo "Build fehlgeschlagen"; exit 1; }

echo "Baue Medienquellen-Helfer …"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 -framework Foundation \
  -o "$APP_PATH/Contents/Resources/NotchMediaSources.dylib" \
  "$SOURCES_DIR/NotchMediaSources.m"
cp "$SOURCES_DIR/notch-media-sources.pl" "$APP_PATH/Contents/Resources/"

echo "Signiere ad hoc …"
codesign --force --deep --sign - "$APP_PATH"

echo "Installiere nach $TARGET_PATH …"
osascript -e 'tell application "DynamicNotch" to quit' >/dev/null 2>&1 || true
sleep 1
if [[ -d "$TARGET_PATH" && ! -d "$TARGET_PATH.original-1.6.3" ]]; then
  mv "$TARGET_PATH" "$TARGET_PATH.original-1.6.3"
else
  rm -rf "$TARGET_PATH"
fi
ditto "$APP_PATH" "$TARGET_PATH"
open "$TARGET_PATH"
echo "Fertig. Die Originalversion liegt unter $TARGET_PATH.original-1.6.3"
