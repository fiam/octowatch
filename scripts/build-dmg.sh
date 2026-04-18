#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME="${OCTOWATCH_DMG_VOLUME_NAME:-Octowatch}"
SETTINGS_PATH="${OCTOWATCH_DMG_SETTINGS:-$ROOT_DIR/scripts/dmg-settings.py}"
DMGBUILD_PACKAGE_SPEC="${OCTOWATCH_DMGBUILD_PACKAGE_SPEC:-dmgbuild==1.6.7}"
BACKGROUND_RENDER_PACKAGE_SPEC="${OCTOWATCH_DMG_RENDER_PACKAGE_SPEC:-pillow}"
BACKGROUND_RENDER_SCRIPT="${OCTOWATCH_DMG_RENDER_SCRIPT:-$ROOT_DIR/scripts/render-dmg-background.py}"
BACKGROUND_PATH="${OCTOWATCH_DMG_BACKGROUND:-}"
TEMP_DIR=""

function cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

function usage() {
  cat <<EOF
usage: $0 --app /path/to/Octowatch.app --output /path/to/Octowatch.dmg [options]

options:
  --volume-name NAME    DMG volume name (default: $VOLUME_NAME)
  --background PATH     Optional custom background image
  --settings PATH       dmgbuild settings file (default: $SETTINGS_PATH)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="${2:-}"
      shift 2
      ;;
    --background)
      BACKGROUND_PATH="${2:-}"
      shift 2
      ;;
    --settings)
      SETTINGS_PATH="${2:-}"
      shift 2
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

if [[ -z "$APP_PATH" || -z "$OUTPUT_PATH" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS_PATH" ]]; then
  echo "settings file not found: $SETTINGS_PATH" >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1 || ! command -v uvx >/dev/null 2>&1; then
  echo "uv is required. Install it first, for example: brew install uv" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
rm -f "$OUTPUT_PATH"

if [[ -z "$BACKGROUND_PATH" ]]; then
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octowatch-dmg-background.XXXXXX")"
  BACKGROUND_PATH="$TEMP_DIR/background.png"
  uv run --with "$BACKGROUND_RENDER_PACKAGE_SPEC" \
    python3 "$BACKGROUND_RENDER_SCRIPT" --output "$BACKGROUND_PATH" --scale 1
  uv run --with "$BACKGROUND_RENDER_PACKAGE_SPEC" \
    python3 "$BACKGROUND_RENDER_SCRIPT" --output "$TEMP_DIR/background@2x.png" --scale 2
fi

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "background image not found: $BACKGROUND_PATH" >&2
  exit 1
fi

dmgbuild_args=(
  --settings "$SETTINGS_PATH"
  -D "app=$APP_PATH"
  -D "background=$BACKGROUND_PATH"
)

APP_ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ -f "$APP_ICON_PATH" ]]; then
  dmgbuild_args+=(-D "badge_icon=$APP_ICON_PATH")
fi

uvx --from "$DMGBUILD_PACKAGE_SPEC" dmgbuild \
  "${dmgbuild_args[@]}" \
  "$VOLUME_NAME" \
  "$OUTPUT_PATH"
