# Octobar

Octobar is a SwiftUI menu bar app for macOS that polls GitHub with a personal access token and highlights work that likely needs your attention.

## What it tracks

- Open pull requests assigned to you
- Actionable GitHub notifications (`review_requested`, `assign`, `mention`, `team_mention`, `ci_activity`, and similar reasons)
- GitHub Actions workflow runs with `status=action_required` where you are the actor

The app polls every 60 seconds and shows local macOS notifications when new actionable items appear.
In the menu, all actionable signals are shown as one attention queue with per-type icons.

## Requirements

- macOS SDK: latest installed (`macosx26.2` on this machine)
- Swift tools 6.2+

## Run

```bash
cd /Users/alberto/Source/octobar
swift build
swift run
```

The app launches as a menu bar utility.

## Token setup

Use a GitHub personal access token (classic or fine-grained) with read access to the repositories you care about. In most setups you will need read permissions for:

- Pull requests / issues metadata
- Actions
- Notifications

The token is stored in macOS Keychain (`dev.octobar.app` service).

If no token is already stored, Octobar will also try importing one automatically from GitHub CLI via `gh auth token` when `gh` is installed and authenticated.

## Notes

- This scaffold uses polling. GitHub push-style event delivery generally requires a GitHub App/webhook setup, which this project intentionally avoids.
- Repository coverage for `action_required` workflow runs is derived from repos already present in your assigned PRs and actionable notifications.
