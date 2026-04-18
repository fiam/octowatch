# Octowatch — Product Requirements Document

## Vision
A native macOS menu-bar app that surfaces GitHub work items requiring
your attention, so nothing slips through the cracks without drowning you
in noise.

## Guiding Principles
1. **Signal over noise** — show only what needs action; hide the rest.
2. **Zero config by default** — works with `gh auth token`, sensible
   defaults, progressive disclosure of power features.
3. **Respect the platform** — standard macOS controls, keyboard idioms,
   Notification Center integration.
4. **Minimal API footprint** — polling only, no GitHub App, conservative
   rate-limit usage.

---

## Shipped Features

### Core Monitoring
- Assigned, authored, and tracked pull requests with 24-type
  classification.
- Issue tracking (created, assigned, mentioned) via dashboard view.
- GitHub notifications with stale-discussion fallback, sourced from both
  read and unread GitHub notification threads.
- Workflow runs tied to tracked PRs (running, succeeded, failed,
  approval-required).
- Post-merge workflow watching with prediction from changed files +
  workflow YAML parsing.

### Inbox & Filtering
- Five scopes: Focus, Pull Requests, Issues, Workflows, Notifications.
- Configurable "Needs Action" rule engine (relationship + signal
  conditions, enable/disable, CRUD, duplicate, reset to defaults),
  including `Ready for Review` and default authored-draft coverage.
- Unread filter on read-state views.
- PR dashboard (created/assigned/mentioned/review-requested) and Issue
  dashboard (created/assigned/mentioned), demand-loaded.
- Sidebar text filter/search across title, repository, actor, and label
  text.
- Multi-select with toolbar + context menu (open / snooze / ignore /
  mark-read / mark-unread).

### Pull Request Detail
- Rich detail pane: body, labels, review threads, checks, commits,
  merge status.
- Authored draft PRs show draft state and support a direct
  ready-for-review action from the detail pane.
- Bot-authored PRs keep their approve-and-merge action even when the
  latest combined row update is a failing check, a comment follow-up, or
  another non-review signal.
- Merge controls with auto-method detection, per-repo memory, merge
  queue support.
- Focused 5 s watch on open PR, 20 s watch on queued PR.
- Post-merge workflow prediction, observed status swap, context badge
  deduplication.
- Rerun check collapsing (latest attempt per logical check).
- Workflow approval sheet (environments, optional comment,
  approve/reject).

### Read State & Notifications
- Dot-style read/unread with auto-mark-read delay (off / 1 / 3 / 5 s).
- Inbox notification visibility comes from the full actionable GitHub
  notification set, while unread state remains local to Octowatch.
- Repository coverage follows GitHub notifications: subscribing to a
  repository on GitHub gives Octowatch more to surface from it, while a
  repository ignored on GitHub stays silent in Octowatch too. Ignoring
  an item in Octowatch only hides it in Octowatch and does not change
  that repository's GitHub notification settings.
- macOS notifications with subject-key threading.
- Self-triggered update suppression toggle.
- Undo affordances for local ignore and snooze actions.

### Settings & Auth
- GitHub CLI token auto-load + manual token entry, with Keychain
  persistence for manually entered tokens.
- Authentication settings include a helper sheet for creating a
  personal access token and opening GitHub token settings directly.
- First-run authentication wizard that appears even when GitHub CLI is
  already ready, walks through repository coverage and default inbox
  sections before the auth choice, explains that Octowatch will reuse
  `gh`, and offers a direct path to switch to a personal access token
  instead.
- Polling interval (30–900 s).
- Rate-limit diagnostics toggle.
- Ignored items and snoozed items managers with restore actions.
- Offline startup handling with a single recovery state, manual retry,
  and automatic reconnect refresh when network access returns.
- Startup authentication guide that reports whether GitHub CLI was
  found, whether manual intervention is required, and how to set up a
  personal access token when needed after initial onboarding.

### Website & Release Infrastructure
- Static marketing/download site source for `octowatch.app`, deployed by
  GitHub Pages.
- GitHub Actions CI for SwiftPM tests, Xcode unit tests, and unsigned
  release-packaging smoke coverage on pull requests and `main`.
- `release-please`-driven GitHub Actions workflow that opens and updates
  Release PRs from Conventional Commits, then on merge creates the
  version tag and GitHub Release, builds universal macOS binaries,
  signs them with Developer ID, notarizes and staples the app + DMG,
  publishes Sparkle appcast metadata, and uploads a generated Homebrew
  cask alongside the release assets before syncing it to a dedicated
  Homebrew tap repository.
- The website resolves the latest published binary release
  automatically, and the app ships with a dedicated tap-installable
  Homebrew cask.
- Local release-packaging script for reproducing unsigned or signed
  release artifacts outside CI, depending on the available credentials.

---

## Roadmap Status

Items below reflect the current implementation status rather than the
initial draft.

### Delivered Since Initial Draft

#### Sidebar Text Filter / Search
Sidebar items can be quick-filtered by title, repository, actor, and
label text.
- **Files:** `AttentionWindowView.swift`, `Models.swift`
- **Status:** Shipped

#### Snooze / Remind-Later
Items can be hidden until a chosen interval expires (1 h, tomorrow,
next week), then resurfaced automatically. Complements ignore
(permanent) with a time-boxed alternative.
- **Files:** `AppModel.swift`, `Models.swift`,
  `AttentionWindowView.swift`, `SnoozedItemsView.swift`
- **Status:** Shipped

#### Draft PR Visual Treatment
Draft pull requests now carry explicit draft labeling in the sidebar
and menu bar, stay eligible for `Your Turn` rules, and authored draft
PRs surface a direct ready-for-review action in the detail pane.
- **Files:** `Models.swift`, `AttentionWindowView.swift`,
  `MenuBarContentView.swift`, `GitHubClient.swift`
- **Status:** Shipped

#### Manual Token Keychain Persistence
Manually entered personal access tokens can now be saved to Keychain,
loaded again on launch, and cleared independently from GitHub CLI.
- **Files:** `KeychainStore.swift`, `SettingsView.swift`,
  `AppModel.swift`
- **Status:** Shipped

### Partial

#### 1. Issue Detail Pane
Issues can be selected and shown in the shared detail surface, but they
still lack a PR-style rich pane with body, assignees, linked PRs, and a
dedicated issue timeline.
- **Files:** `AttentionWindowView.swift`, `GitHubClient.swift`,
  `Models.swift`
- **API:** `GET /repos/{owner}/{repo}/issues/{number}` + timeline
- **Status:** Partial

#### 2. Batch Mark-Read / Mark-All-Read
Multi-select mark-read and mark-unread exist, but there are still no
"Mark section read" or "Mark all read" actions in the sidebar or
toolbar.
- **Files:** `AppModel.swift`, `AttentionWindowView.swift`
- **Status:** Partial

#### 3. Keyboard Navigation Improvements
Cmd+R and Cmd+Shift+U exist, but Enter-to-open, Delete/Backspace to
ignore, and Cmd+Shift+A mark-all-read are still missing.
- **Files:** `AttentionWindowView.swift`
- **Status:** Partial

#### 4. Expanded Test Coverage
- Integration tests for `AppModel` polling loop with a stub client are
  still missing.
- UI coverage exists for auto-mark-read plus targeted draft-PR and
  security-alert presentation paths, but the wider UI surface is still
  not comprehensively covered.
- Settings persistence round-trip tests are still missing.
- **Files:** `Tests/`
- **Status:** Partial

### Missing

#### 5. Stale PR Indicator
Flag PRs with no activity for a configurable period (for example,
7 days) so authored PRs do not disappear into the background.
- **Files:** `Models.swift`, `AttentionWindowView.swift`
- **Status:** Missing

#### 6. Deep-Link Support (`octobar://`)
Register a custom URL scheme so external tools / scripts can open
specific items in the app.
- **Files:** `AppDelegate.swift`, `Info.plist`, `project.yml`
- **Status:** Missing

---

## Non-Goals (for now)
- GitHub App / webhook-based real-time updates.
- Cross-platform (iOS, Linux).
- Organization-wide dashboards or team views.
- Broad GitHub write tooling beyond targeted actions such as ready for
  review, merge, and workflow approval.

---

## Architecture Notes
- **Polling model:** single `AppModel` polling loop, default 60 s.
- **Search budget:** ~6 search API calls per poll cycle + 1 per team
  membership. Issue tracking deferred to the Issues dashboard; workflow
  watch candidates derived from already-fetched PR data; open+merged
  queries combined into single calls with in-memory splitting.
- **Token:** `gh` CLI is preferred when available; manually entered
  personal access tokens are saved in Keychain and reused on launch.
- **Persistence:** `UserDefaults` for read state, ignored items,
  snoozed items, rules, and preferences; versioned keys.
- **Build:** SwiftPM primary, XcodeGen for `.xcodeproj` generation.
- **Release automation:** GitHub Actions for CI, Pages deployment,
  release-please versioning, universal binary packaging, Developer ID
  signing, Apple notarization, Sparkle appcast publishing, Homebrew
  cask generation, and dedicated tap publishing.
- **Deps:** Yams (YAML parsing for workflow prediction).
