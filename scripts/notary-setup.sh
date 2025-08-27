#!/usr/bin/env bash
set -euo pipefail

# Configure a keychain profile for xcrun notarytool using an App Store Connect API key.
# Prereqs: You must create an API key (.p8) in App Store Connect (Users and Access > Keys).
# Inputs via env vars or flags:
#   ISSUER   - App Store Connect Issuer ID (uuid)
#   KEY_ID   - App Store Connect Key ID (e.g. ABCDEFGHIJ)
#   KEY_PATH - Path to the .p8 private key
#   PROFILE  - Keychain profile name to save (default: macutil-notary)
# Example:
#   ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx KEY_ID=ABCDEF1234 KEY_PATH=~/AuthKey_ABCDEF1234.p8 \
#     scripts/notary-setup.sh

PROFILE="${PROFILE:-macutil-notary}"
ISSUER="${ISSUER:-}"
KEY_ID="${KEY_ID:-}"
KEY_PATH="${KEY_PATH:-}"

if [[ -z "$ISSUER" || -z "$KEY_ID" || -z "$KEY_PATH" ]]; then
  echo "Usage: ISSUER=<issuer-id> KEY_ID=<key-id> KEY_PATH=/path/to/key.p8 PROFILE=<name> $0" >&2
  exit 2
fi

if [ ! -f "$KEY_PATH" ]; then
  echo "Key file not found: $KEY_PATH" >&2
  exit 3
fi

echo "Storing notarytool credentials in keychain profile: $PROFILE"
xcrun notarytool store-credentials "$PROFILE" \
  --issuer "$ISSUER" \
  --key-id "$KEY_ID" \
  --key "$KEY_PATH"

echo "Done. Test with: xcrun notarytool info --keychain-profile $PROFILE --list 2>/dev/null || true"
