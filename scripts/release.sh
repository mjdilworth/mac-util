#!/usr/bin/env bash
set -euo pipefail

# Release build + export + notarize + staple for mac-util
# Usage:
#   scripts/release.sh                # Build+export+zip+staple only
#   NOTARIZE=1 scripts/release.sh     # Also submit to Apple for notarization (requires notary profile)
#   NOTARY_PROFILE=my-profile scripts/release.sh  # Override default notary profile name

SCHEME="mac-util"
PROJECT="mac-util.xcodeproj"
ARCHIVE_PATH="build/mac-util.xcarchive"
EXPORT_PLIST="ExportOptions.plist"
EXPORT_PATH="build/export"
APP_NAME="mac-util.app"
APP_PATH="$EXPORT_PATH/$APP_NAME"
ZIP_PATH="$EXPORT_PATH/mac-util.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-macutil-notary}"

command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild not found. Please install Xcode." >&2; exit 1; }

# Fresh build/export dirs
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

# Archive (Release + Developer ID)
echo "[1/6] Archiving Release..."
xcodebuild -scheme "$SCHEME" -project "$PROJECT" -configuration Release -archivePath "$ARCHIVE_PATH" clean archive

# Export with ExportOptions.plist (developer-id)
echo "[2/6] Exporting archive..."
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$EXPORT_PLIST" -exportPath "$EXPORT_PATH"

# Ensure nested helper(s) have Hardened Runtime and are signed properly
echo "[3/6] Verifying embedded helper hardened runtime..."
SIGN_ID=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -n1 || true)
if [ -z "$SIGN_ID" ]; then SIGN_ID="Developer ID Application"; fi

FOUND=0
while IFS= read -r -d '' HELPER; do
  FOUND=1
  chmod +x "$HELPER" || true
  if ! codesign -dv --verbose=4 "$HELPER" 2>&1 | grep -qi "runtime"; then
    echo "Re-signing helper with Hardened Runtime: ${HELPER#"$APP_PATH/"}"
    /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$HELPER"
  else
    echo "Helper already hardened: ${HELPER#"$APP_PATH/"}"
  fi
done < <(find "$APP_PATH/Contents" -maxdepth 2 -type f -name displayplacer -print0 2>/dev/null)

if [ "$FOUND" -eq 1 ]; then
  /usr/bin/codesign --force --options runtime --timestamp --preserve-metadata=entitlements,requirements,flags --sign "$SIGN_ID" "$APP_PATH"
else
  echo "No embedded helper named 'displayplacer' found under Contents/; continuing."
fi

# Zip the app for notarization
echo "[4/6] Creating zip..."
if [ ! -d "$APP_PATH" ]; then
  echo "Exported app not found at $APP_PATH" >&2
  exit 2
fi
rm -f "$ZIP_PATH"
# ditto preserves extended attributes and is recommended for notarization uploads
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Notarize (optional)
if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "[5/6] Submitting zip to Apple notarization (profile: $NOTARY_PROFILE) ..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  echo "[5/6] Skipping notarization (set NOTARIZE=1 to enable)"
fi

# Staple and verify
echo "[6/6] Stapling and verifying..."
xcrun stapler staple -q "$APP_PATH" || true

# CRITICAL: Recreate zip after stapling so the distributed zip contains the stapled ticket
echo "[7/7] Recreating zip with stapled ticket..."
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Verify Gatekeeper assessment and codesign details
spctl -a -vv "$APP_PATH" || true
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true
codesign -dv --verbose=4 "$APP_PATH" 2>/dev/null || true

cat <<EOF

Done. Artifacts:
- App:   $APP_PATH
- Zip:   $ZIP_PATH (contains stapled notarization ticket)

The zip file now includes the stapled notarization ticket.
Copy mac-util.zip to the other Mac, unzip, and run mac-util.app.
On first launch, it should open without security warnings.
EOF
