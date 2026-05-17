#!/usr/bin/env bash
#
# TestFlight upload — one-shot archive + export + upload.
#
# Prerequisites (one-time):
#   1. Apple Developer Program enrollment active.
#   2. Replace <TEAM_ID> below AND in scripts/ExportOptions.plist with the
#      10-char Team ID from developer.apple.com → Membership.
#   3. Patch project.yml: set DEVELOPMENT_TEAM (project-level settings.base
#      and on each target's settings.base) + CODE_SIGN_STYLE: Automatic.
#   4. App Group group.com.jlgao.PrefrontalCortex registered at
#      developer.apple.com → Identifiers → App Groups.
#   5. App record created at appstoreconnect.apple.com (bundle id
#      com.jlgao.PrefrontalCortex).
#   6. App Store Connect API key — set the env vars below.
#
# Run this script — it auto-bumps the build number (UTC-minute
# timestamp) so App Store Connect never sees a duplicate. Override
# with BUILD_NUMBER=... if you need a specific value.
#
#   ASC_API_KEY_ID=<KeyID> ASC_API_KEY_ISSUER=<IssuerID> \
#     bash scripts/testflight_upload.sh

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="<TEAM_ID>"
SCHEME="PrefrontalCortex"
ARCHIVE_PATH="build/PrefrontalCortex.xcarchive"
EXPORT_PATH="build/export"
IPA_PATH="$EXPORT_PATH/$SCHEME.ipa"

# Required env vars for non-interactive upload via altool:
#   ASC_API_KEY_ID      — 10-char Key ID from App Store Connect → Users and
#                         Access → Integrations → App Store Connect API
#   ASC_API_KEY_ISSUER  — Issuer ID from the same page
#   ASC_API_KEY_PATH    — path to the downloaded AuthKey_<KEY_ID>.p8 (xcrun
#                         also auto-discovers from ~/.appstoreconnect/private_keys/)
: "${ASC_API_KEY_ID:?Set ASC_API_KEY_ID before running}"
: "${ASC_API_KEY_ISSUER:?Set ASC_API_KEY_ISSUER before running}"

# xcodebuild needs the App Store Connect API key explicitly for both
# archive and export: there is no signed-in Xcode account in this
# headless context, so without it `-allowProvisioningUpdates` can't
# mint the iOS Distribution certificate / App Store profile and export
# dies with "No Accounts / No signing certificate iOS Distribution".
# xcrun also auto-discovers the .p8 from ~/.appstoreconnect/private_keys.
ASC_API_KEY_PATH="${ASC_API_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY_ID}.p8}"
[ -f "$ASC_API_KEY_PATH" ] || { echo "API key .p8 not found: $ASC_API_KEY_PATH"; exit 1; }
AUTH_FLAGS=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_API_KEY_PATH"
  -authenticationKeyID "$ASC_API_KEY_ID"
  -authenticationKeyIssuerID "$ASC_API_KEY_ISSUER"
)

# Auto-bump the build number. App Store Connect rejects duplicate
# CFBundleVersion for a (bundle id, marketing version). A UTC minute
# timestamp is monotonic, never collides, and is human-readable
# (YYYYMMDDHHMM). Set in project.yml — the source of truth; xcodegen
# regenerates project.pbxproj from it on the next line. Override with
# BUILD_NUMBER=... if a specific value is needed.
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
echo "→ build number → $BUILD_NUMBER"
/usr/bin/sed -i '' \
  "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" \
  project.yml
grep -q "CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"" project.yml \
  || { echo "build-number bump failed (project.yml unchanged)"; exit 1; }

# Auto-increment the marketing version's last component every push
# (0.1 → 0.2 → 0.3 …; the build NUMBER alone bumping isn't visible as
# a new "Version" in App Store Connect — TestFlight groups builds
# under MARKETING_VERSION). Stays on by default until told otherwise;
# set MARKETING_VERSION=x.y to pin a specific value, or
# SKIP_VERSION_BUMP=1 to leave it alone.
if [ -z "${SKIP_VERSION_BUMP:-}" ]; then
  if [ -n "${MARKETING_VERSION:-}" ]; then
    NEW_MV="$MARKETING_VERSION"
  else
    CUR_MV="$(grep -E 'MARKETING_VERSION: "' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
    MV_HEAD="${CUR_MV%.*}"; MV_TAIL="${CUR_MV##*.}"
    if [ "$MV_HEAD" = "$CUR_MV" ]; then     # single component, e.g. "1"
      NEW_MV="$((CUR_MV + 1))"
    else
      NEW_MV="${MV_HEAD}.$((MV_TAIL + 1))"
    fi
  fi
  echo "→ marketing version → $NEW_MV"
  /usr/bin/sed -i '' \
    "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW_MV\"/" \
    project.yml
  grep -q "MARKETING_VERSION: \"$NEW_MV\"" project.yml \
    || { echo "marketing-version bump failed (project.yml unchanged)"; exit 1; }
fi

echo "→ regenerating Xcode project"
xcodegen generate

echo "→ archiving"
# -allowProvisioningUpdates: first signed archive of this app — let
# Xcode create the iCloud container + distribution provisioning
# profiles headlessly instead of failing.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj \
  -scheme "$SCHEME" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  "${AUTH_FLAGS[@]}" \
  archive

echo "→ exporting IPA"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  "${AUTH_FLAGS[@]}"

echo "→ uploading to App Store Connect"
xcrun altool --upload-app \
  -f "$IPA_PATH" \
  -t ios \
  --apiKey "$ASC_API_KEY_ID" \
  --apiIssuer "$ASC_API_KEY_ISSUER"

echo "✓ uploaded. Processing in App Store Connect takes ~10 min."
echo "  Check status: https://appstoreconnect.apple.com/apps"
