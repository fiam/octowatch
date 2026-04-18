#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
RELEASE_TAG="${OCTOWATCH_RELEASE_TAG:-v$VERSION}"
REPOSITORY="${OCTOWATCH_REPOSITORY:-fiam/octowatch}"
DOWNLOAD_URL_PREFIX="${OCTOWATCH_DOWNLOAD_URL_PREFIX:-https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG}"
LATEST_DOWNLOAD_URL_PREFIX="${OCTOWATCH_LATEST_DOWNLOAD_URL_PREFIX:-https://github.com/$REPOSITORY/releases/latest/download}"
BUILD_NUMBER="${OCTOWATCH_BUILD_NUMBER:-1}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "version may only contain letters, numbers, dots, underscores, and dashes" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "build number must be an integer" >&2
  exit 1
fi

DERIVED_DATA_PATH="$ROOT_DIR/.derived-release"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_CACHE_PATH="$DERIVED_DATA_PATH/PackageCache"
CLONED_SOURCE_PACKAGES_PATH="$DERIVED_DATA_PATH/SourcePackages"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Octowatch.app"
APP_EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Octowatch"
APPCAST_DIR="$DIST_DIR/appcast"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.sparkle-tools"
VERSIONED_ZIP_NAME="Octowatch-${VERSION}.zip"
VERSIONED_DMG_NAME="Octowatch-${VERSION}.dmg"
LATEST_ZIP_NAME="Octowatch.zip"
LATEST_DMG_NAME="Octowatch.dmg"
CASK_NAME="octowatch.rb"
APPCAST_NAME="appcast.xml"

SIGNED_RELEASE=false
NOTARIZED_RELEASE=false
SPARKLE_APPCAST=false

function require_env() {
  local name
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      echo "missing required environment variable: $name" >&2
      exit 1
    fi
  done
}

function notarize() {
  local path="$1"
  xcrun notarytool submit "$path" \
    --key "$OCTOWATCH_NOTARY_KEY_FILE" \
    --key-id "$OCTOWATCH_NOTARY_KEY_ID" \
    --issuer "$OCTOWATCH_NOTARY_ISSUER_ID" \
    --wait
}

if [[ -n "${OCTOWATCH_CODESIGN_IDENTITY:-}" || -n "${OCTOWATCH_APPLE_TEAM_ID:-}" || -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  require_env OCTOWATCH_CODESIGN_IDENTITY OCTOWATCH_APPLE_TEAM_ID SPARKLE_PUBLIC_ED_KEY
  SIGNED_RELEASE=true
fi

if [[ -n "${OCTOWATCH_NOTARY_KEY_FILE:-}" || -n "${OCTOWATCH_NOTARY_KEY_ID:-}" || -n "${OCTOWATCH_NOTARY_ISSUER_ID:-}" ]]; then
  require_env OCTOWATCH_NOTARY_KEY_FILE OCTOWATCH_NOTARY_KEY_ID OCTOWATCH_NOTARY_ISSUER_ID
  NOTARIZED_RELEASE=true
fi

if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  SPARKLE_APPCAST=true
  "$ROOT_DIR/scripts/setup-sparkle-tools.sh"
fi

rm -rf "$DERIVED_DATA_PATH" "$DIST_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$PACKAGE_CACHE_PATH" "$CLONED_SOURCE_PACKAGES_PATH"

pushd "$ROOT_DIR" >/dev/null

xcodegen generate

xcodebuild_args=(
  -project Octowatch.xcodeproj
  -scheme Octowatch
  -configuration Release
  -derivedDataPath "$DERIVED_DATA_PATH"
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH"
  -packageCachePath "$PACKAGE_CACHE_PATH"
  -destination "platform=macOS"
  ONLY_ACTIVE_ARCH=NO
  ARCHS="arm64 x86_64"
  MARKETING_VERSION="$VERSION"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  -quiet
)

if [[ "$SIGNED_RELEASE" == "true" ]]; then
  xcodebuild_args+=(
    DEVELOPMENT_TEAM="$OCTOWATCH_APPLE_TEAM_ID"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$OCTOWATCH_CODESIGN_IDENTITY"
    OTHER_CODE_SIGN_FLAGS=--timestamp
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY"
  )
else
  xcodebuild_args+=(
    CODE_SIGNING_ALLOWED=NO
  )
fi

xcodebuild "${xcodebuild_args[@]}" build

if [[ ! -d "$APP_PATH" ]]; then
  echo "expected app not found at $APP_PATH" >&2
  exit 1
fi

ACTUAL_ARCHES="$(lipo -archs "$APP_EXECUTABLE_PATH")"
for expected_arch in arm64 x86_64; do
  if [[ " $ACTUAL_ARCHES " != *" $expected_arch "* ]]; then
    echo "missing expected architecture slice: $expected_arch" >&2
    echo "found architectures: $ACTUAL_ARCHES" >&2
    exit 1
  fi
done

if [[ "$SIGNED_RELEASE" == "true" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

if [[ "$NOTARIZED_RELEASE" == "true" ]]; then
  notarize "$APP_PATH"
  xcrun stapler staple "$APP_PATH"
fi

ditto -c -k --sequesterRsrc --keepParent \
  "$APP_PATH" \
  "$DIST_DIR/$VERSIONED_ZIP_NAME"

if [[ "$SPARKLE_APPCAST" == "true" ]]; then
  rm -rf "$APPCAST_DIR"
  mkdir -p "$APPCAST_DIR"
  cp "$DIST_DIR/$VERSIONED_ZIP_NAME" "$APPCAST_DIR/"

  appcast_args=(
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --link "https://octowatch.app"
    -o "$APPCAST_NAME"
    "$APPCAST_DIR"
  )

  printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | \
    "$SPARKLE_TOOLS_DIR/bin/generate_appcast" \
      --ed-key-file - \
      "${appcast_args[@]}"

  cp "$APPCAST_DIR/$APPCAST_NAME" "$DIST_DIR/$APPCAST_NAME"
fi

"$ROOT_DIR/scripts/build-dmg.sh" \
  --app "$APP_PATH" \
  --output "$DIST_DIR/$VERSIONED_DMG_NAME" \
  --volume-name "Octowatch"

if [[ "$NOTARIZED_RELEASE" == "true" ]]; then
  notarize "$DIST_DIR/$VERSIONED_DMG_NAME"
  xcrun stapler staple "$DIST_DIR/$VERSIONED_DMG_NAME"
fi

cp "$DIST_DIR/$VERSIONED_ZIP_NAME" "$DIST_DIR/$LATEST_ZIP_NAME"
cp "$DIST_DIR/$VERSIONED_DMG_NAME" "$DIST_DIR/$LATEST_DMG_NAME"

DMG_SHA256="$(shasum -a 256 "$DIST_DIR/$VERSIONED_DMG_NAME" | awk '{print $1}')"
OCTOWATCH_HOMEBREW_CASK_VERSION="$VERSION" \
OCTOWATCH_HOMEBREW_CASK_SHA256="$DMG_SHA256" \
OCTOWATCH_HOMEBREW_CASK_URL="$DOWNLOAD_URL_PREFIX/$VERSIONED_DMG_NAME" \
  "$ROOT_DIR/scripts/generate-homebrew-cask.sh" > "$DIST_DIR/$CASK_NAME"

checksum_inputs=(
  "$VERSIONED_ZIP_NAME"
  "$VERSIONED_DMG_NAME"
  "$LATEST_ZIP_NAME"
  "$LATEST_DMG_NAME"
  "$CASK_NAME"
)

if [[ -f "$DIST_DIR/$APPCAST_NAME" ]]; then
  checksum_inputs+=("$APPCAST_NAME")
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "${checksum_inputs[@]}" > checksums.txt
)

cat > "$DIST_DIR/release-metadata.json" <<EOF
{
  "version": "$VERSION",
  "buildNumber": "$BUILD_NUMBER",
  "tag": "$RELEASE_TAG",
  "repository": "$REPOSITORY",
  "architectures": "$ACTUAL_ARCHES",
  "signed": $SIGNED_RELEASE,
  "notarized": $NOTARIZED_RELEASE,
  "zip": "$VERSIONED_ZIP_NAME",
  "dmg": "$VERSIONED_DMG_NAME",
  "latestZip": "$LATEST_ZIP_NAME",
  "latestDmg": "$LATEST_DMG_NAME",
  "homebrewCask": "$CASK_NAME",
  "downloadURLPrefix": "$DOWNLOAD_URL_PREFIX",
  "latestDownloadURLPrefix": "$LATEST_DOWNLOAD_URL_PREFIX"
}
EOF

rm -rf "$APPCAST_DIR"

popd >/dev/null
