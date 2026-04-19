#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.derived-data"
APP_BUNDLE_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Octowatch.app"
APP_EXECUTABLE_PATH="$APP_BUNDLE_PATH/Contents/MacOS/Octowatch"
MAIN_OUTPUT_PATH="$ROOT_DIR/website/assets/readme-main-window.png"
TMP_DIR="$ROOT_DIR/.tmp-website-screenshots"

function wait_for_window_id() {
  local window_id

  for _ in {1..60}; do
    window_id="$(
      swift - <<'SWIFT'
import Foundation
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

let candidates = windows.compactMap { window -> (Int, Int)? in
    guard
        let owner = window[kCGWindowOwnerName as String] as? String,
        owner == "Octowatch",
        let layer = window[kCGWindowLayer as String] as? Int,
        layer == 0,
        let number = window[kCGWindowNumber as String] as? Int,
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? Int,
        let height = bounds["Height"] as? Int
    else {
        return nil
    }

    return (number, width * height)
}

if let window = candidates.max(by: { $0.1 < $1.1 }) {
    print(window.0)
}
SWIFT
    )"

    if [[ -n "$window_id" ]]; then
      printf '%s\n' "$window_id"
      return 0
    fi

    sleep 0.25
  done

  echo "failed to find Octowatch window" >&2
  return 1
}

function build_app() {
  pushd "$ROOT_DIR" >/dev/null
  xcodegen generate >/dev/null
  xcodebuild \
    -project Octowatch.xcodeproj \
    -scheme Octowatch \
    -configuration Debug \
    -sdk macosx \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    -quiet
  popd >/dev/null
}

function launch_fixture() {
  local fixture_name="$1"

  pkill -x Octowatch >/dev/null 2>&1 || true

  OCTOWATCH_LAUNCH_FIXTURE="$fixture_name" \
    "$APP_EXECUTABLE_PATH" >/tmp/octowatch-capture.log 2>&1 &

  sleep 1.5
  osascript -e 'tell application "Octowatch" to activate' >/dev/null 2>&1 || true
}

function capture_fixture() {
  local fixture_name="$1"
  local output_path="$2"
  local raw_path
  local window_id

  raw_path="$TMP_DIR/$(basename "$output_path" .png)-raw.png"

  launch_fixture "$fixture_name"
  window_id="$(wait_for_window_id)"

  screencapture -x -l "$window_id" "$raw_path"
  sips -Z 1600 "$raw_path" --out "$output_path" >/dev/null
}

mkdir -p "$TMP_DIR"

build_app
capture_fixture "website-demo" "$MAIN_OUTPUT_PATH"

pkill -x Octowatch >/dev/null 2>&1 || true
rm -rf "$TMP_DIR"

echo "Updated website screenshots:"
echo "  $MAIN_OUTPUT_PATH"
