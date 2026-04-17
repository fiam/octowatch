#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="${OCTOWATCH_REPOSITORY:-fiam/octowatch}"
RELEASES_URL="https://github.com/${REPOSITORY}/releases/latest/download/Octowatch.dmg"

cat <<EOF
cask "octowatch" do
  version :latest
  sha256 :no_check

  url "${RELEASES_URL}",
      verified: "github.com/${REPOSITORY}/"
  name "Octowatch"
  desc "Native macOS triage inbox for GitHub work"
  homepage "https://octowatch.app"

  auto_updates true

  app "Octowatch.app"

  zap trash: [
    "~/Library/Application Support/Octowatch",
    "~/Library/Caches/app.octowatch.macos",
    "~/Library/HTTPStorages/app.octowatch.macos",
    "~/Library/Preferences/app.octowatch.macos.plist",
    "~/Library/Saved Application State/app.octowatch.macos.savedState"
  ]
end
EOF
