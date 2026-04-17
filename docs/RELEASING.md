# Releasing Octowatch

Octowatch releases are automated through GitHub Actions with
`release-please`.

## Release Flow

1. Pushes to `main` run the `Release` workflow in
   [`.github/workflows/release.yml`](../.github/workflows/release.yml).
2. `release-please` opens or updates a Release PR from Conventional
   Commits, [`version.txt`](../version.txt), and
   [`CHANGELOG.md`](../CHANGELOG.md).
3. When that Release PR is merged, the next push to `main` creates the
   `v<version>` tag and GitHub Release.
4. The same workflow run builds the macOS release and uploads the public
   artifacts to that GitHub Release.

`workflow_dispatch` is also available if you need to force the next
version number with `release_as`.

## Published Artifacts

Each published release includes:

- `Octowatch-<version>.dmg`
- `Octowatch-<version>.zip`
- `Octowatch.dmg`
- `Octowatch.zip`
- `appcast.xml`
- `octowatch.rb`
- `checksums.txt`
- `release-metadata.json`

The versioned assets are the immutable release artifacts. The stable
asset names are used by the website, Sparkle feed, and Homebrew cask to
point at the latest release.

## Versioning

`release-please` is configured by:

- [`release-please-config.json`](../release-please-config.json)
- [`.release-please-manifest.json`](../.release-please-manifest.json)
- [`version.txt`](../version.txt)
- [`CHANGELOG.md`](../CHANGELOG.md)

Use Conventional Commits for changes that should participate in version
calculation and changelog generation.
