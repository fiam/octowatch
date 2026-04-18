#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="${OCTOWATCH_REPOSITORY:-fiam/octowatch}"
VERSION="${OCTOWATCH_HOMEBREW_CASK_VERSION:-}"
SHA256="${OCTOWATCH_HOMEBREW_CASK_SHA256:-}"
DOWNLOAD_URL="${OCTOWATCH_HOMEBREW_CASK_URL:-}"

if [[ -n "$VERSION" || -n "$SHA256" || -n "$DOWNLOAD_URL" ]]; then
  if [[ -z "$VERSION" || -z "$SHA256" || -z "$DOWNLOAD_URL" ]]; then
    echo "versioned cask generation requires version, sha256, and download URL" >&2
    exit 1
  fi

  VERSION_LINE="  version \"$VERSION\""
  SHA256_LINE="  sha256 \"$SHA256\""
else
  DOWNLOAD_URL="https://github.com/${REPOSITORY}/releases/latest/download/Octowatch.dmg"
  VERSION_LINE="  version :latest"
  SHA256_LINE="  sha256 :no_check"
fi

cat <<EOF
cask "octowatch" do
${VERSION_LINE}
${SHA256_LINE}

  url "${DOWNLOAD_URL}",
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
