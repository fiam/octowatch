#!/usr/bin/env bash

set -euo pipefail

APP_REPOSITORY="${OCTOWATCH_REPOSITORY:-fiam/octowatch}"
TAP_REPOSITORY="${OCTOWATCH_HOMEBREW_TAP_REPOSITORY:-fiam/homebrew-tap}"
TAP_OWNER="${TAP_REPOSITORY%%/*}"
TAP_REPO_NAME="${TAP_REPOSITORY#*/}"
TAP_NAME="${TAP_REPO_NAME#homebrew-}"

cat <<EOF
# Homebrew Tap

This tap publishes Homebrew casks for projects from
[${TAP_OWNER}](https://github.com/${TAP_OWNER}).

## Install

\`\`\`bash
brew install --cask ${TAP_OWNER}/${TAP_NAME}/octowatch
\`\`\`

## About

- Octowatch: https://github.com/${APP_REPOSITORY}
- Releases: https://github.com/${APP_REPOSITORY}/releases

The casks in this tap are updated automatically by their respective
release workflows.
EOF
