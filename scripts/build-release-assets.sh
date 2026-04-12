#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

DERIVED_DATA_PATH="$ROOT_DIR/.derived-release"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Octowatch.app"
DMG_STAGING_DIR="$DIST_DIR/dmg"
ZIP_NAME="Octowatch-${VERSION}.zip"
DMG_NAME="Octowatch-${VERSION}.dmg"

rm -rf "$DERIVED_DATA_PATH" "$DIST_DIR"
mkdir -p "$DIST_DIR"

pushd "$ROOT_DIR" >/dev/null

xcodegen generate

xcodebuild \
  -project Octowatch.xcodeproj \
  -scheme Octowatch \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "expected app not found at $APP_PATH" >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent \
  "$APP_PATH" \
  "$DIST_DIR/$ZIP_NAME"

rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "Octowatch" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$DMG_NAME" \
  >/dev/null

(
  cd "$DIST_DIR"
  shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > checksums.txt
)

cat > "$DIST_DIR/release-metadata.json" <<EOF
{
  "version": "$VERSION",
  "zip": "$ZIP_NAME",
  "dmg": "$DMG_NAME"
}
EOF

rm -rf "$DMG_STAGING_DIR"

popd >/dev/null
