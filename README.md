# Octowatch

Octowatch is a SwiftUI macOS app with a status item and a detailed
attention window. It polls GitHub with a token and highlights work that
likely needs your attention.

## What it tracks

- Open pull requests assigned to you
- Recently merged pull requests you authored, reviewed, commented on, or were still assigned when they merged, kept in the pull request stream as a log
- Actionable GitHub notifications (`review_requested`, `assign`, `mention`, `team_mention`, `ci_activity`, and similar reasons)
- GitHub Actions workflow runs with `status=action_required` where you are the actor

The app polls every 60 seconds and shows local macOS notifications when new actionable items appear.
The menu bar icon uses an unread-dot indicator instead of a numeric badge.
In the menu, all actionable signals are shown as one inbox with per-type icons.
Items also have dot-style read/unread indicators, and opening an item marks it as read locally.
Items can also be ignored locally, and ignored subjects can be restored later from Settings.
Pull request detail panes read repository workflow files and PR changed paths to predict which push workflows should run after merge, then swap to observed post-merge workflow statuses once GitHub starts them.

## Requirements

- macOS SDK: latest installed (`macosx26.2` on this machine)
- Swift tools 6.2+

## Run

```bash
cd /Users/alberto/Source/octobar
swift build
swift run
```

If you want to open the app in Xcode, generate the local project first:

```bash
xcodegen generate
open Octowatch.xcodeproj
```

The generated `.xcodeproj` is local-only and is not committed.

The app launches with a Dock icon, a status item, and a main attention
window for more detailed triage.

## Token setup

Use a GitHub personal access token (classic or fine-grained) with read access to the repositories you care about. In most setups you will need read permissions for:

- Pull requests / issues metadata
- Actions
- Notifications

If `gh` is installed and authenticated, Octowatch will try `gh auth token`
first and validate it before using it.

You can also enter a custom token in Settings. Custom tokens are
session-only and are not written to Keychain.

Because Octowatch reads GitHub notifications, the token must work with the
Notifications API. GitHub's documentation says the "List notifications
for the authenticated user" endpoint does not work with fine-grained
personal access tokens.

## Notes

- This scaffold uses polling. GitHub push-style event delivery generally requires a GitHub App/webhook setup, which this project intentionally avoids.
- Workflow watching covers PRs you authored, approved, or merged, and
  it sends local notifications when queued pull requests actually merge
  and when post-merge workflows finish with success or failure.
