# Releasing Octowatch

This repo now includes the first public-release scaffolding:

- a GitHub Pages site published from [`website/`](../website)
- a CI workflow that exercises SwiftPM tests, Xcode unit tests, and the
  unsigned release-packaging path
- a tag-driven GitHub Actions workflow that builds unsigned macOS
  release artifacts and publishes a draft GitHub Release

Signing, notarization, Sparkle publishing, and Homebrew cask publishing
are intentionally not included yet.

## Current Release Flow

1. Either push a tag like `v1.2.3` or manually run the `Release`
   workflow with `version: 1.2.3`.
2. GitHub Actions validates that the version matches the expected
   release format and derives the release tag as `v<version>`.
3. GitHub Actions builds the app in `Release` mode with
   `CODE_SIGNING_ALLOWED=NO`.
4. The workflow packages:
   - `Octowatch-<version>.zip`
   - `Octowatch-<version>.dmg`
   - `checksums.txt`
   - `release-metadata.json`
5. The workflow creates or updates a draft GitHub Release for
   `v<version>` and uploads those files.

Manual dispatch is useful when you want a draft release from the current
commit without pushing the tag first. In that case, the workflow creates
the `v<version>` tag from the triggering commit SHA.

The workflow lives in
[`release.yml`](../.github/workflows/release.yml), and the packaging
logic is kept in
[`scripts/build-release-assets.sh`](../scripts/build-release-assets.sh)
so the same steps can run locally.

## Current CI Flow

The CI workflow lives in [`ci.yml`](../.github/workflows/ci.yml) and
currently runs on pull requests, pushes to `main`, and manual dispatch.
It covers:

- `swift test`
- Xcode unit tests via `xcodebuild test`
- a release smoke test via
  [`build-release-assets.sh`](../scripts/build-release-assets.sh)

The smoke-test job uploads `checksums.txt` and `release-metadata.json`
as short-lived workflow artifacts so packaging failures can be debugged
without waiting for a tagged release.

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
- `release-metadata.json`

## Follow-Up Work

Before public distribution is complete, add:

- Developer ID signing
- Apple notarization and stapling
- Sparkle archive signing and appcast publishing
- Homebrew tap automation
- release versioning sourced from project settings instead of manual tag
  discipline
