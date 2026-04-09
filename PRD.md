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
- macOS notifications with subject-key threading.
- Self-triggered update suppression toggle.
- Undo affordances for local ignore and snooze actions.

### Settings & Auth
- GitHub CLI token auto-load + manual token entry (session-only).
- Polling interval (30–900 s).
- Rate-limit diagnostics toggle.
- Ignored items and snoozed items managers with restore actions.

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
- UI coverage exists for auto-mark-read, but the wider UI surface is not
  yet covered.
- Settings persistence round-trip tests are still missing.
- **Files:** `Tests/`
- **Status:** Partial

### Missing

#### 5. Draft PR Visual Treatment
Draft state exists in the model/API layer, but the UI still does not
give draft pull requests a distinct treatment.
- **Files:** `Models.swift`, `AttentionWindowView.swift`,
  `GitHubClient.swift`
- **Status:** Missing

#### 6. Stale PR Indicator
Flag PRs with no activity for a configurable period (for example,
7 days) so authored PRs do not disappear into the background.
- **Files:** `Models.swift`, `AttentionWindowView.swift`
- **Status:** Missing

#### 7. Persist Token in Keychain
`KeychainStore.swift` exists but is still unused. Users should be able
to opt in to persisting their token across launches.
- **Files:** `KeychainStore.swift`, `SettingsView.swift`,
  `AppModel.swift`
- **Status:** Missing

#### 8. Deep-Link Support (`octobar://`)
Register a custom URL scheme so external tools / scripts can open
specific items in the app.
- **Files:** `AppDelegate.swift`, `Info.plist`, `project.yml`
- **Status:** Missing

---

## Non-Goals (for now)
- GitHub App / webhook-based real-time updates.
- Cross-platform (iOS, Linux).
- Organization-wide dashboards or team views.
- Write operations beyond merge and workflow approval.

---

## Architecture Notes
- **Polling model:** single `AppModel` polling loop, default 60 s.
- **Search budget:** ~6 search API calls per poll cycle + 1 per team
  membership. Issue tracking deferred to the Issues dashboard; workflow
  watch candidates derived from already-fetched PR data; open+merged
  queries combined into single calls with in-memory splitting.
- **Token:** runtime-only from `gh` CLI or manual entry; Keychain
  available but unused.
- **Persistence:** `UserDefaults` for read state, ignored items,
  snoozed items, rules, and preferences; versioned keys.
- **Build:** SwiftPM primary, XcodeGen for `.xcodeproj` generation.
- **Deps:** Yams (YAML parsing for workflow prediction).
