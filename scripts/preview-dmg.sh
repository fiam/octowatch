#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH=""
VERSION="${OCTOWATCH_PREVIEW_VERSION:-0.0.0-preview}"
OUTPUT_PATH="${OCTOWATCH_PREVIEW_DMG_PATH:-$ROOT_DIR/.dmg-preview/Octowatch-preview.dmg}"
DERIVED_DATA_PATH="${OCTOWATCH_PREVIEW_DERIVED_DATA:-$ROOT_DIR/.derived-dmg-preview}"
VOLUME_NAME="${OCTOWATCH_DMG_VOLUME_NAME:-Octowatch}"
OPEN_DMG=true
BACKGROUND_PATH="${OCTOWATCH_DMG_BACKGROUND:-}"
build_dmg_args=()

function usage() {
  cat <<EOF
usage: $0 [options]

options:
  --app PATH            Package an existing app bundle instead of building one
  --version VERSION     MARKETING_VERSION for preview builds (default: $VERSION)
  --output PATH         Output DMG path (default: $OUTPUT_PATH)
  --background PATH     Optional custom background image
  --no-open             Build the DMG but do not mount/open it
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --background)
      BACKGROUND_PATH="${2:-}"
      shift 2
      ;;
    --no-open)
      OPEN_DMG=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  rm -rf "$DERIVED_DATA_PATH"

  pushd "$ROOT_DIR" >/dev/null
  xcodegen generate
  xcodebuild \
    -project Octowatch.xcodeproj \
    -scheme Octowatch \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "platform=macOS" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION=1 \
    CODE_SIGNING_ALLOWED=NO \
    build \
    -quiet
  popd >/dev/null

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Octowatch.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app not found: $APP_PATH" >&2
  exit 1
fi

if [[ -n "$BACKGROUND_PATH" ]]; then
  build_dmg_args+=(--background "$BACKGROUND_PATH")
fi

"$ROOT_DIR/scripts/build-dmg.sh" \
  --app "$APP_PATH" \
  --output "$OUTPUT_PATH" \
  --volume-name "$VOLUME_NAME" \
  "${build_dmg_args[@]}"

echo "Preview DMG created at $OUTPUT_PATH"

if [[ "$OPEN_DMG" == "true" ]]; then
  if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
    hdiutil detach "/Volumes/$VOLUME_NAME" >/dev/null 2>&1 || true
  fi
  open "$OUTPUT_PATH"
fi
