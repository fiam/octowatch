#!/usr/bin/env bash

set -euo pipefail

APP_REPOSITORY="${OCTOWATCH_REPOSITORY:-fiam/octowatch}"
TAP_REPOSITORY="${OCTOWATCH_HOMEBREW_TAP_REPOSITORY:-fiam/homebrew-octowatch}"
TAP_OWNER="${TAP_REPOSITORY%%/*}"
TAP_REPO_NAME="${TAP_REPOSITORY#*/}"
TAP_NAME="${TAP_REPO_NAME#homebrew-}"

cat <<EOF
# Homebrew Tap For Octowatch

This tap publishes the Homebrew cask for
[Octowatch](https://github.com/${APP_REPOSITORY}).

## Install

\`\`\`bash
brew install --cask ${TAP_OWNER}/${TAP_NAME}/octowatch
\`\`\`

## About

- App repository: https://github.com/${APP_REPOSITORY}
- Website: https://octowatch.app
- Releases: https://github.com/${APP_REPOSITORY}/releases

The cask in this tap is updated automatically by the Octowatch release
workflow whenever a new notarized release is published.
EOF
