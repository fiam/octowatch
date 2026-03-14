# AGENTS.md

## Purpose
This file captures project-specific guidance for coding agents working in `octobar`.

## Project Summary
- App: macOS app with a status item, main window, and settings, built
  with Swift + SwiftUI.
- Goal: surface GitHub work items that need attention.
- Runtime model: GitHub API polling (default every 60s), no GitHub App required.

## Source Of Truth
- Use `xcodegen` for Xcode project generation.
- Treat `project.yml` as canonical project config.
- Do not commit generated `.xcodeproj` contents.
- Do not hand-edit `Octowatch.xcodeproj/project.pbxproj` unless explicitly requested.
- For UI work, follow Apple's Human Interface Guidelines:
  https://developer.apple.com/design/human-interface-guidelines
- Prefer standard macOS controls, settings window conventions, spacing,
  and interaction patterns unless the user explicitly asks for a custom
  treatment.

## Common Commands
- Generate Xcode project:
  - `xcodegen generate`
- Build with SwiftPM:
  - `swift build`
- Run with SwiftPM:
  - `swift run`
- Build with Xcode CLI:
  - `xcodebuild -project Octowatch.xcodeproj -scheme Octowatch -configuration Debug -sdk macosx build`

## Key Files
- `project.yml`: Xcode project definition.
- `Octobar/Info.plist`: app metadata.
- `Sources/Octobar/AppModel.swift`: app state, polling loop, notifications.
- `Sources/Octobar/GitHubClient.swift`: GitHub API integration and snapshot assembly.
- `Sources/Octobar/MenuBarContentView.swift`: menu bar UI.
- `Sources/Octobar/AttentionWindowView.swift`: detailed main window UI.
- `Sources/Octobar/SettingsView.swift`: token and polling settings.
- `Sources/Octobar/GitHubCLITokenProvider.swift`: runtime token loading from `gh`.

## GitHub Integration Notes
- Primary views tracked:
  - assigned pull requests
  - actionable notifications
  - action-required workflow runs
- Items related to already closed or merged pull requests should be filtered out.
- Prefer conservative API usage and keep polling interval at or above 60s unless user asks otherwise.

## Security And Privacy
- Default token source is GitHub CLI via `gh auth token`, read at runtime.
- User-entered custom tokens are session-only and are not persisted.
- Never print tokens or persist them in logs/files.
- Keep token scopes minimal for read-only monitoring.

## Change Workflow
- For app behavior changes:
  1. Update Swift sources.
  2. Run `swift build`.
  3. If project settings changed, update `project.yml`, then run `xcodegen generate`.
  4. Validate Xcode build via `xcodebuild`.
- Update `README.md` when user-facing behavior changes.

## Commit Conventions
- Use Conventional Commit subjects (`type(scope): summary` or `type: summary`).
- Every commit must include both a title and a body.
- Follow idiomatic Git line lengths:
  - subject line: 50 chars or fewer
  - body lines: 72 chars or fewer

## Current Constraints
- Without GitHub App/webhooks, notifications are polling-based.
- User-level push notifications from GitHub for this exact use case are not available.
