# AGENTS.md

## Purpose
This file captures project-specific guidance for coding agents working in `octobar`.

## Project Summary
- App: macOS menu bar app built with Swift + SwiftUI.
- Goal: surface GitHub work items that need attention.
- Runtime model: GitHub API polling (default every 60s), no GitHub App required.

## Source Of Truth
- Use `xcodegen` for Xcode project generation.
- Treat `project.yml` as canonical project config.
- Do not hand-edit `Octobar.xcodeproj/project.pbxproj` unless explicitly requested.

## Common Commands
- Generate Xcode project:
  - `xcodegen generate`
- Build with SwiftPM:
  - `swift build`
- Run with SwiftPM:
  - `swift run`
- Build with Xcode CLI:
  - `xcodebuild -project Octobar.xcodeproj -scheme Octobar -configuration Debug -sdk macosx build`

## Key Files
- `project.yml`: Xcode project definition.
- `Octobar/Info.plist`: app metadata (`LSUIElement=true` for menu bar behavior).
- `Sources/Octobar/AppModel.swift`: app state, polling loop, notifications.
- `Sources/Octobar/GitHubClient.swift`: GitHub API integration and snapshot assembly.
- `Sources/Octobar/MenuBarContentView.swift`: menu bar UI.
- `Sources/Octobar/SettingsView.swift`: token and polling settings.
- `Sources/Octobar/KeychainStore.swift`: PAT storage in Keychain.

## GitHub Integration Notes
- Primary views tracked:
  - assigned pull requests
  - actionable notifications
  - action-required workflow runs
- Items related to already closed or merged pull requests should be filtered out.
- Prefer conservative API usage and keep polling interval at or above 60s unless user asks otherwise.

## Security And Privacy
- Personal access token is stored in Keychain (`service: dev.octobar.app`).
- On startup, if Keychain has no token, app may import one from GitHub CLI via `gh auth token`.
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
