Release build and run on another Mac

Prereqs
- Xcode with command line tools
- Developer ID Application certificate in your login keychain (same Apple ID as team 8CQNFLS235)
- Optional: App Store Connect API key for notarization (recommended)

One-time: set up notary credentials
1) Create an API key in App Store Connect (Users and Access > Keys) and download the .p8 file.
2) Store credentials in keychain:
   ISSUER=<issuer-uuid> KEY_ID=<key-id> KEY_PATH=/path/to/AuthKey_<KEY_ID>.p8 \
   scripts/notary-setup.sh
   This creates a keychain profile named macutil-notary.

Build, export, zip, notarize, staple
- Build+export only:
  scripts/release.sh
- Build+export+notarize+staple:
  NOTARIZE=1 scripts/release.sh

Artifacts
- App: build/export/mac-util.app
- Zip: build/export/mac-util.zip (share this with others)

Run on another Mac
- Copy mac-util.zip to the other Mac, unzip, and run mac-util.app
- If macOS still warns, right-click > Open once; notarization+stapling should allow normal launch afterward.

Troubleshooting
- Verify signature and Gatekeeper:
  spctl -a -vv build/export/mac-util.app
  codesign --verify --deep --strict --verbose=2 build/export/mac-util.app
- If signing fails during export, ensure a valid Developer ID Application cert is installed and selected for Release.
- If notarization fails, re-run with NOTARIZE=1 after fixing credentials (scripts/notary-setup.sh) and check network/firewall.
