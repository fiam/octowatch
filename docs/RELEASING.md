# Releasing Octowatch

This repo now includes the first public-release scaffolding:

- a GitHub Pages site published from [`website/`](../website)
- a tag-driven GitHub Actions workflow that builds unsigned macOS
  release artifacts and publishes a draft GitHub Release

Signing, notarization, Sparkle publishing, and Homebrew cask publishing
are intentionally not included yet.

## Current Release Flow

1. Push a tag like `v1.2.3`.
2. GitHub Actions builds the app in `Release` mode with
   `CODE_SIGNING_ALLOWED=NO`.
3. The workflow packages:
   - `Octowatch-<version>.zip`
   - `Octowatch-<version>.dmg`
   - `checksums.txt`
4. The workflow creates a draft GitHub Release and uploads those files.

The workflow lives in
[`release.yml`](../.github/workflows/release.yml), and the packaging
logic is kept in
[`scripts/build-release-assets.sh`](../scripts/build-release-assets.sh)
so the same steps can run locally.

## Current Website Flow

The static site lives in [`website/`](../website). The Pages workflow
publishes it to GitHub Pages and includes:

- the landing page
- the custom domain file for `octowatch.app`
- release lookup logic that reads the latest published GitHub Release

The website does not host binaries directly. It links to the latest
published GitHub Release assets.

## Local Build

To build unsigned release assets locally:

```bash
./scripts/build-release-assets.sh 1.2.3
```

Artifacts are written to `dist/`:

- `Octowatch-1.2.3.zip`
- `Octowatch-1.2.3.dmg`
- `checksums.txt`

## Follow-Up Work

Before public distribution is complete, add:

- Developer ID signing
- Apple notarization and stapling
- Sparkle archive signing and appcast publishing
- Homebrew tap automation
- release versioning sourced from project settings instead of manual tag
  discipline
