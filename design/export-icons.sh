#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SVG="$ROOT/design/octowatch-app-icon.svg"
MENU_SVG="$ROOT/design/octowatch-menubar.svg"
MENU_ALERT_SVG="$ROOT/design/octowatch-menubar-alert.svg"
APPICON_DIR="$ROOT/Sources/Octobar/Assets.xcassets/AppIcon.appiconset"
MENU_DIR="$ROOT/Sources/Octobar/Assets.xcassets/MenuBarIcon.imageset"
MENU_ALERT_DIR="$ROOT/Sources/Octobar/Assets.xcassets/MenuBarIconAlert.imageset"

render_png() {
  local size="$1"
  local filename="$2"
  rsvg-convert -w "$size" -h "$size" "$APP_SVG" -o "$APPICON_DIR/$filename"
}

render_png 16 icon_16x16.png
render_png 32 icon_16x16@2x.png
render_png 32 icon_32x32.png
render_png 64 icon_32x32@2x.png
render_png 128 icon_128x128.png
render_png 256 icon_128x128@2x.png
render_png 256 icon_256x256.png
render_png 512 icon_256x256@2x.png
render_png 512 icon_512x512.png
render_png 1024 icon_512x512@2x.png

rsvg-convert -f pdf "$MENU_SVG" -o "$MENU_DIR/menu-bar-icon.pdf"
rsvg-convert -f pdf "$MENU_ALERT_SVG" -o "$MENU_ALERT_DIR/menu-bar-icon-alert.pdf"
