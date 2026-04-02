# Octowatch

Octowatch is a SwiftUI macOS app with a status item and a detailed
attention window. It polls GitHub with a token and highlights work that
likely needs your attention.

## What it tracks

- Open pull requests assigned to you
- Open pull requests you authored when they are ready to merge, have merge conflicts, or have failed checks
- Recently merged pull requests you authored, reviewed, commented on, or were still assigned when they merged, kept in the pull request stream as a log
- Actionable GitHub notifications (`review_requested`, `assign`, `mention`, `team_mention`, `ci_activity`, and similar reasons)
- GitHub Actions workflow runs attached to pull requests you authored, reviewed, were assigned, or merged, including waiting-for-approval and failed runs

The app polls every 60 seconds and shows local macOS notifications when new actionable items appear.
The menu bar icon uses an unread-dot indicator instead of a numeric badge.
In the menu, each pull request or issue now appears only once, even when GitHub surfaces multiple notifications or workflow updates for the same subject. The row shows the latest state plus a secondary relationship badge when relevant.
Those stacked badges use a compact two-line tooltip in both the sidebar and detail view when a secondary badge is present.
When Octowatch is referring to your own GitHub account as the actor in the UI, it renders that label as `you` while keeping the underlying GitHub profile links unchanged.
Bot accounts keep their badge in the compact sidebar and all-updates actor labels, and those visible labels omit the literal `[bot]` suffix.
The detail pane keeps an all-updates timeline at the bottom of pull request details, and that history is persisted locally so older updates still appear when the subject drops out of the API and later returns.
Local macOS notifications also reuse the same subject identity, so newer updates replace older notifications for that pull request or issue instead of leaving stale duplicates behind. Settings include a toggle for whether updates triggered by your own comments, commits, reviews, and workflows should raise macOS notifications; the default is off, but those self-triggered updates still stay in the timeline.
Items in the `Inbox` view have dot-style read/unread indicators, and opening one of those items marks it as read locally. The `Browse` dashboards (`My PRs` and `My Issues`) do not use local read state.
The unread-only filter in `Inbox` keeps the current session stable like Mail, so items that were visible when you entered that filter do not disappear immediately after being marked read.
The main window also includes native search for the current scope, matching titles, repositories, labels, and common attention metadata without leaving the app.
The main window sidebar supports native macOS multi-selection, and a right-click menu can open, snooze, ignore, and, where read state is supported, mark the current selection read or unread.
Ignoring and snoozing from the main window both show a small transient undo toast so accidental local triage actions can be reversed quickly.
Items can also be ignored or snoozed locally, and those subjects can be restored later from separate `Ignored Items` and `Snoozed Items` windows in Settings without forcing an immediate GitHub refresh.
Pull request detail panes surface merge conflicts alongside review threads and check results, follow GitHub's pull-request merge UI to pick the applicable merge method automatically when only one direct-merge option is available, keep the method selector inside the merge button when multiple options are available, remember the last method you chose per repository, read repository workflow files and PR changed paths to predict which push workflows should run after merge, explain which workflow files could not be evaluated and why, then swap to observed post-merge workflow statuses once GitHub starts them. When a tracked post-merge workflow status matches the selected item's primary state, the detail header suppresses the duplicate context pill and only shows distinct workflow attention badges. Workflow runs waiting for approval now open a native review sheet that lists the pending environments, supports optional comments, and can approve or reject them directly; GitHub remains available as a fallback from that sheet, and the same review flow is reachable from sidebar buttons, update rows, post-merge workflow rows, and the menu bar. The currently open pull request detail also stays on a focused 5-second watch, queued-to-merge pull requests keep a slower background watch so the app can refresh them to `Merged` shortly after GitHub actually merges them, and workflow failures or approval-gated post-merge runs discovered in that focused refresh now promote the pull request into `Your Turn` immediately. Transient workflow-preview fetch misses no longer blank the last known post-merge workflow card from the open detail pane, and rerun checks now collapse to the latest attempt for each logical check so stale failures do not keep a pull request red after a successful rerun.
Single-item detail panes and main-window sidebar rows also show GitHub labels for pull requests and issues when Octowatch has them available. In the detail pane, clicking a label opens the matching GitHub search for that repository and subject type.
Loading a pull request's detail pane also feeds fresher label and review-state data back into the inbox model immediately, so the row and update history do not need to wait for the next polling cycle to catch up.
Merged pull requests keep the actual merge time visible in the detail header, add a separate last-update timestamp only when later PR-related activity differs, and ignore scheduled/default-branch workflow runs that are not attributable to that merge.
When a single item is selected, `Cmd+R` forces a refresh of that subject and bypasses the cached pull-request focus payload.
When the same account both creates and assigns a pull request, the detail header collapses that metadata into a single "created and assigned by" fact.
Approved pull requests also show both the creator and approver in the detail header, and collapse that to "created and approved by" when the same account did both.
For PRs you already reviewed, new commits since your review are called out near the top of the detail pane and the commit action is labeled accordingly.
Settings also include an optional diagnostics toggle that adds per-bucket GitHub API budget details to the inbox sidebar for debugging rate-limit behavior.
The main window has two modes: `Inbox` for triaging actionable items and `Browse` for viewing your pull requests and issues. `Inbox` shows a pinned `Your Turn` section at the top with items matching your rules, followed by all other activity grouped by type (pull requests, issues, workflows, notifications). Items in `Your Turn` are deduplicated from the stream below. `Unread` is a separate filter available in `Inbox`. `Browse` switches between `My PRs` and `My Issues` dashboards with open-item filters such as `Created`, `Assigned`, `Mentioned`, and `Review Requests` for pull requests. Dashboards are fetched on demand instead of on every background poll; `My PRs` opens on the `Created` filter by default, while `My Issues` opens on `Assigned`. The main window keeps its split view mounted while those scope-specific loads happen, blanks the detail pane during the transition, and confines the loading indicator to the left sidebar instead of obscuring the whole window; the left sidebar also opens at a roomier default width. The `Your Turn` section is driven by editable rules in Settings: you can add, duplicate, remove, enable, and disable rules, choose whether each rule targets pull requests, issues, or workflows, and build each rule from inline conditions for relationships, status signals, and your review state. All conditions in a rule must match, and each condition can be excluded when you want to express the opposite case. Workflow rules are signal-based, including failed runs, approval-waiting runs, and queued or running runs. Approval-waiting workflows include GitHub runs that report `waiting` when the viewer can approve their pending deployment. Workflow watch selection now prefers the most recently updated related pull requests within each relationship bucket so recent approval-gated post-merge runs do not get crowded out by older high-numbered PRs, and merged pull requests remain eligible for workflow watching for a week so long-running post-merge approvals can still surface in `Your Turn`. Issue rules currently focus on responsibility relationships, and workflow rules can still match pull-request rows when those rows carry current workflow activity. The menu bar popover shows only `Your Turn` items for quick triage, with each item opening directly in GitHub.

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
- Workflow watching covers PRs you authored, reviewed, were assigned, or merged, and
  it sends local notifications when queued pull requests actually merge
  and when post-merge workflows start waiting for approval or, once the
  observed post-merge push runs settle, finish with success or failure.
