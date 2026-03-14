# Octobar

Octobar is a SwiftUI menu bar app for macOS that polls GitHub with a personal access token and highlights work that likely needs your attention.

## What it tracks

- Open pull requests assigned to you
- Actionable GitHub notifications (`review_requested`, `assign`, `mention`, `team_mention`, `ci_activity`, and similar reasons)
- GitHub Actions workflow runs with `status=action_required` where you are the actor

The app polls every 60 seconds and shows local macOS notifications when new actionable items appear.
In the menu, all actionable signals are shown as one attention queue with per-type icons.
Items also have dot-style read/unread indicators, and opening an item marks it as read locally.

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

If `gh` is installed and authenticated, Octobar will try `gh auth token`
first and validate it before using it.

You can also enter a custom token in Settings. Custom tokens are
session-only and are not written to Keychain.

Because Octobar reads GitHub notifications, the token must work with the
Notifications API. GitHub's documentation says the "List notifications
for the authenticated user" endpoint does not work with fine-grained
personal access tokens.

## Notes

- This scaffold uses polling. GitHub push-style event delivery generally requires a GitHub App/webhook setup, which this project intentionally avoids.
- Repository coverage for `action_required` workflow runs is derived from repos already present in your assigned PRs and actionable notifications.
