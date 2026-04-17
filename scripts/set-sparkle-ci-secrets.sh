#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID=""
REPO=""
ENVIRONMENT=""

function usage() {
  cat <<'EOF'
Usage:
  scripts/set-sparkle-ci-secrets.sh --bundle-id <bundle-id> [--repo <owner/repo>] [--env <environment>]

Notes:
  - Reads the Sparkle key from the synchronizable Keychain item stored as
    account `sparkle: <bundle-id>`.
  - Sets `SPARKLE_PRIVATE_ED_KEY` as a GitHub Actions secret.
  - Sets `SPARKLE_PUBLIC_ED_KEY` as a GitHub Actions variable.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --env)
      ENVIRONMENT="${2:-}"
      shift 2
      ;;
    --help|-h)
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

if [[ -z "$BUNDLE_ID" ]]; then
  echo "--bundle-id is required" >&2
  usage >&2
  exit 1
fi

gh_secret_args=()
gh_variable_args=()

if [[ -n "$REPO" ]]; then
  gh_secret_args+=(-R "$REPO")
  gh_variable_args+=(-R "$REPO")
fi

if [[ -n "$ENVIRONMENT" ]]; then
  gh_secret_args+=(--env "$ENVIRONMENT")
  gh_variable_args+=(--env "$ENVIRONMENT")
fi

PRIVATE_KEY="$("$ROOT_DIR/scripts/sparkle-keychain.swift" export-secret --bundle-id "$BUNDLE_ID")"
PUBLIC_KEY="$("$ROOT_DIR/scripts/sparkle-keychain.swift" print-public-key --bundle-id "$BUNDLE_ID")"

gh secret set SPARKLE_PRIVATE_ED_KEY "${gh_secret_args[@]}" --body "$PRIVATE_KEY"
gh variable set SPARKLE_PUBLIC_ED_KEY "${gh_variable_args[@]}" --body "$PUBLIC_KEY"

echo "Updated Sparkle CI credentials for bundle ID '$BUNDLE_ID'."
