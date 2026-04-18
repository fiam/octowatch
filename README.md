<p align="center">
  <img src="docs/images/icon-source.png" alt="Octowatch logo" width="128">
</p>

# Octowatch

Octowatch is a native macOS app that watches GitHub and pulls the work
that needs your attention into one place.

It lives in the menu bar, opens into a full triage window when you need
more context, and focuses on actionable pull requests, notifications,
workflow runs, and security alerts without requiring a GitHub App or
webhooks.

## Screenshots

![Octowatch main window](docs/images/readme-main-window.png)

![Octowatch first-run setup](docs/images/readme-onboarding.png)

## What It Does

- Builds a single inbox from pull requests, issues, workflows, and
  GitHub notifications
- Highlights a `Your Turn` section with configurable rules for what
  needs action now
- Shows rich pull request detail with checks, review threads, timeline,
  merge state, and direct actions
- Tracks workflow failures and approval-gated deployments connected to
  your pull requests
- Surfaces GitHub security alerts without collapsing them into generic
  comment notifications
- Supports local read state, snoozing, ignoring, undo, and a menu bar
  quick-view for fast triage

## Authentication

Octowatch prefers GitHub CLI when it is available:

- if `gh` is installed and authenticated, Octowatch reuses
  `gh auth token`
- if you do not want to use GitHub CLI, you can enter a personal access
  token in Settings
- Settings includes a helper sheet that explains how to create a token
  and links directly to GitHub token settings
- manually entered tokens are saved in Keychain for future launches

On first launch, Octowatch always shows a setup guide so the auth path
is explicit. The guide first explains how GitHub notifications shape
repository coverage, then how the default `Your Turn` and
`On Your Radar` inbox sections work, and finally how Octowatch will
authenticate on this Mac. If GitHub CLI is already ready, the guide
tells you that Octowatch will use it and still offers a direct path to
switch to a personal access token.

Because Octowatch reads GitHub notifications, the token must work with
the Notifications API. In practice, that usually means:

- classic personal access tokens work
- fine-grained personal access tokens are often not enough for the
  notifications endpoints Octowatch depends on

Repository coverage follows GitHub notifications:

- subscribe to a repository on GitHub if you want Octowatch to surface
  more of that repository's activity
- if a repository is ignored on GitHub, GitHub stops sending those
  notifications and Octowatch will stay silent about that repository too
- ignoring an item in Octowatch only hides it in Octowatch; it does not
  change your notification settings for that repository on GitHub

## Requirements

- macOS 26 or newer
- Swift 6.2+
- XcodeGen for local Xcode project generation

## Install

Published releases are universal (`arm64` + `x86_64`), Developer ID
signed, notarized, and support Sparkle in-app updates.

- Direct download: [octowatch.app](https://octowatch.app) or
  [GitHub Releases](https://github.com/fiam/octowatch/releases)
- Homebrew:

```bash
brew install --cask fiam/octowatch/octowatch
```

## Getting Started

To run Octowatch from source:

```bash
git clone <repo-url>
cd octowatch
swift build
swift run
```

If you want to work in Xcode:

```bash
xcodegen generate
open Octowatch.xcodeproj
```

The generated `.xcodeproj` is local-only and is not committed.

## Website And Releases

- The project website sources live in [`website/`](website/).
- GitHub Pages deployment is defined in
  [`.github/workflows/pages.yml`](.github/workflows/pages.yml).
- CI validation is defined in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
- Release automation is defined in
  [`.github/workflows/release.yml`](.github/workflows/release.yml).
- Releases are versioned with `release-please`; see
  [docs/RELEASING.md](docs/RELEASING.md) for the public release flow.

## Product Notes

- Polling only. No GitHub App, webhooks, or background service
  required.
- Default refresh interval is 60 seconds.
- GitHub notification threads are fetched from both read and unread
  feeds, while the inbox read/unread state remains local to Octowatch.
- If the app starts while offline, it shows a dedicated recovery state
  and retries automatically when connectivity returns.

## Roadmap

The current shipped scope and remaining gaps live in
[PRD.md](PRD.md).

The main items still open are:

- richer issue detail
- mark-section-read / mark-all-read actions
- deeper keyboard navigation
- stale PR indicators
- deep-link support

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
