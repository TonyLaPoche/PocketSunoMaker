#!/usr/bin/env bash
set -euo pipefail

#
# Build, sign, notarize and verify a macOS release artifact.
#
# Example:
#   CERT_NAME="Developer ID Application: Terrade Antoine (K934D5JR7T)" \
#   ./scripts/macos_notarize_release.sh --version v0.1.1 --notary-profile AC_PROFILE
#

TEAM_ID_DEFAULT="K934D5JR7T"
NOTARY_PROFILE_DEFAULT="AC_PROFILE"
APP_BUNDLE_DEFAULT="pocketsunomaker.app"
BUILD_OUTPUT_DIR_DEFAULT="build/macos/Build/Products/Release"

VERSION_TAG=""
CERT_NAME="${CERT_NAME:-}"
TEAM_ID="${TEAM_ID:-$TEAM_ID_DEFAULT}"
NOTARY_PROFILE="${NOTARY_PROFILE:-$NOTARY_PROFILE_DEFAULT}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-$APP_BUNDLE_DEFAULT}"
BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-$BUILD_OUTPUT_DIR_DEFAULT}"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage:
  macos_notarize_release.sh --version <tag> [options]

Required:
  --version <tag>            Release tag/version, e.g. v0.1.1

Optional:
  --cert-name <name>         Full signing identity name
                             (or set CERT_NAME env var)
  --team-id <team>           Apple Team ID (default: K934D5JR7T)
  --notary-profile <name>    notarytool keychain profile (default: AC_PROFILE)
  --app-bundle <name>        App bundle name in Release dir (default: pocketsunomaker.app)
  --build-output-dir <path>  Build output dir (default: build/macos/Build/Products/Release)
  --skip-build               Skip flutter build step
  -h, --help                 Show this help

Notes:
  - You must have a valid Developer ID Application certificate installed.
  - You must configure notarytool keychain profile beforehand, e.g.:
      xcrun notarytool store-credentials "AC_PROFILE" --apple-id "<apple-id>" --team-id "<team-id>" --password "<app-specific-password>"
EOF
}

log() {
  printf "\n[%s] %s\n" "$(date +'%H:%M:%S')" "$*"
}

fail() {
  printf "\nError: %s\n" "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION_TAG="${2:-}"
      shift 2
      ;;
    --cert-name)
      CERT_NAME="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --app-bundle)
      APP_BUNDLE_NAME="${2:-}"
      shift 2
      ;;
    --build-output-dir)
      BUILD_OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$VERSION_TAG" ]] || fail "--version is required"
[[ -n "$CERT_NAME" ]] || fail "Missing certificate identity. Provide --cert-name or CERT_NAME."

if [[ "$CERT_NAME" != *"($TEAM_ID)"* ]]; then
  fail "Certificate identity does not contain Team ID $TEAM_ID: $CERT_NAME"
fi

command -v flutter >/dev/null 2>&1 || fail "flutter is not installed"
command -v codesign >/dev/null 2>&1 || fail "codesign is not available"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is not available"
command -v ditto >/dev/null 2>&1 || fail "ditto is not available"
command -v shasum >/dev/null 2>&1 || fail "shasum is not available"
command -v spctl >/dev/null 2>&1 || fail "spctl is not available"

APP_PATH="$BUILD_OUTPUT_DIR/$APP_BUNDLE_NAME"
APP_BASENAME="${APP_BUNDLE_NAME%.app}"
ZIP_PATH="$BUILD_OUTPUT_DIR/PocketSunoMaker-macos-${VERSION_TAG}.zip"
ZIP_SHA_PATH="$ZIP_PATH.sha256"
TMP_ZIP_PATH="$BUILD_OUTPUT_DIR/notary-upload-${VERSION_TAG}.zip"

log "Release pipeline configuration"
echo "Version tag:      $VERSION_TAG"
echo "Team ID:          $TEAM_ID"
echo "Certificate:      $CERT_NAME"
echo "Notary profile:   $NOTARY_PROFILE"
echo "App bundle:       $APP_PATH"
echo "Final zip:        $ZIP_PATH"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  log "Building Flutter macOS release"
  flutter build macos --release
else
  log "Skipping Flutter build (--skip-build)"
fi

[[ -d "$APP_PATH" ]] || fail "App bundle not found: $APP_PATH"

log "Signing app bundle with hardened runtime"
codesign --force --deep --options runtime --timestamp --sign "$CERT_NAME" "$APP_PATH"

log "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" >/dev/null

log "Creating temporary zip for notarization upload"
rm -f "$TMP_ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$TMP_ZIP_PATH"

log "Submitting to Apple notarization service (this can take several minutes)"
xcrun notarytool submit "$TMP_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

log "Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

log "Validating stapled ticket"
xcrun stapler validate "$APP_PATH"

log "Gatekeeper assessment"
spctl -a -t exec -vv "$APP_PATH"

log "Building final distributable zip from stapled app"
rm -f "$ZIP_PATH" "$ZIP_SHA_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

log "Computing SHA256"
shasum -a 256 "$ZIP_PATH" | tee "$ZIP_SHA_PATH"

log "Done"
echo "Artifact: $ZIP_PATH"
echo "SHA file: $ZIP_SHA_PATH"
echo "Suggested release title: PocketSunoMaker $VERSION_TAG"
