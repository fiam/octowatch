# Contributing to Octowatch

Thanks for contributing.

## Before You Start

- Open an issue before starting large features or behavioral changes.
- Keep pull requests focused. Small, reviewable changes are preferred.
- Follow standard macOS conventions unless the change explicitly requires
  a custom interaction or visual treatment.

## Development Setup

```bash
swift build
xcodegen generate
xcodebuild -project Octowatch.xcodeproj -scheme Octowatch \
  -configuration Debug -sdk macosx build
```

For UI work, generate the local Xcode project with `xcodegen generate`.
`project.yml` is the source of truth. Do not hand-edit generated
`.xcodeproj` contents.

## Testing

Before opening a pull request, run:

```bash
swift test
xcodebuild -project Octowatch.xcodeproj -scheme Octowatch \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

If your change touches UI behavior, also run the relevant UI test target
or add targeted UI coverage when reasonable.

## Change Expectations

- Update `README.md` when user-facing behavior changes.
- Update `PRD.md` when shipped behavior, roadmap state, or notable gaps
  change.
- Keep token handling conservative. Never log or commit credentials.
- Prefer minimal API usage and avoid lowering the default polling
  interval without a clear reason.

## Pull Requests

Please include:

- a short explanation of the problem being solved
- the approach you chose
- any screenshots or recordings for visible UI changes
- test coverage notes, or an explanation of what was validated manually

## Commit Style

Conventional Commit subjects are preferred, for example:

- `fix(menu-bar): stabilize popover sizing`
- `feat(auth): add first-run setup flow`

Keep commit messages clear and scoped to one logical change.
