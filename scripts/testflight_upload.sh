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
# Then bump CURRENT_PROJECT_VERSION in project.yml and run this script.
# App Store Connect rejects duplicate build numbers.

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
  -allowProvisioningUpdates \
  archive

echo "→ exporting IPA"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates

echo "→ uploading to App Store Connect"
xcrun altool --upload-app \
  -f "$IPA_PATH" \
  -t ios \
  --apiKey "$ASC_API_KEY_ID" \
  --apiIssuer "$ASC_API_KEY_ISSUER"

echo "✓ uploaded. Processing in App Store Connect takes ~10 min."
echo "  Check status: https://appstoreconnect.apple.com/apps"
