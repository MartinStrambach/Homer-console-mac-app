#!/usr/bin/env bash
# Shared configuration for release scripts. Source this from every script.
# Exits non-zero if required env vars are missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="$PROJECT_ROOT/.env.release"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

die() {
  echo "error: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "$name is not set. Define it in $ENV_FILE or export it in your shell."
  fi
}

require_env DEVELOPER_ID_APPLICATION
require_env APPLE_TEAM_ID
require_env NOTARY_PROFILE

APP_NAME="Homer Console"
SCHEME="HomerConsole"
BUNDLE_ID="com.martinstrambach.HomerConsole"
XCODEPROJ="$PROJECT_ROOT/App/HomerConsole.xcodeproj"
PROJECT_YML="$PROJECT_ROOT/App/project.yml"

BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
ARCHIVE_PATH="$BUILD_DIR/HomerConsole.xcarchive"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/HomerConsole.zip"

parse_version() {
  # MARKETING_VERSION is defined per-configuration in the committed pbxproj, which xcodegen
  # writes from App/project.yml; the Debug and Release values match, so the first match is
  # authoritative. check-tools.sh verifies the YAML says the same.
  grep -m1 'MARKETING_VERSION = ' "$XCODEPROJ/project.pbxproj" \
    | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' \
    | tr -d ' "'
}

VERSION="$(parse_version)"
if [[ -z "$VERSION" ]]; then
  die "Could not parse MARKETING_VERSION from $XCODEPROJ/project.pbxproj"
fi

DMG_PATH="$DIST_DIR/HomerConsole-$VERSION.dmg"

# Release builds resolve packages here rather than into DerivedData, so the tools Sparkle ships
# in its package artifact (sign_update, generate_keys) are at a path the scripts can rely on.
SOURCE_PACKAGES_DIR="$BUILD_DIR/SourcePackages"
SPARKLE_BIN="$SOURCE_PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"

# The keychain account of the Sparkle signing key. `ed25519` is generate_keys' default, the key
# Bridge Commander signs with too, so one key serves both apps. A key of this app's own would
# be `generate_keys --account <name>`, set here and as SUPublicEDKey in App/HomerConsole/Info.plist.
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"

# The Sparkle feed published next to the DMG. The app reads it from the newest GitHub release
# (SUFeedURL in App/HomerConsole/Info.plist points at releases/latest/download/appcast.xml).
APPCAST_PATH="$DIST_DIR/appcast.xml"

# Records the git commit the artifacts in dist/ were built from, so publishing
# can refuse to ship a DMG that predates the current checkout. File mtimes are
# not usable for this: stapling and validating both touch the DMG.
REVISION_FILE="$DIST_DIR/.build-revision"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

export SCRIPT_DIR PROJECT_ROOT APP_NAME SCHEME BUNDLE_ID XCODEPROJ \
       BUILD_DIR DIST_DIR ARCHIVE_PATH APP_PATH ZIP_PATH VERSION DMG_PATH \
       REVISION_FILE SOURCE_PACKAGES_DIR SPARKLE_BIN SPARKLE_KEY_ACCOUNT APPCAST_PATH PROJECT_YML
