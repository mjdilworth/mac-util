Release build and run on another Mac

Prereqs
- Xcode with command line tools
- Developer ID Application certificate in your login keychain (same Apple ID as team 8CQNFLS235)
- Optional: App Store Connect API key for notarization (recommended)

One-time: set up notary credentials
1) Go to App Store Connect: https://appstoreconnect.apple.com/access/api
   - Sign in with your Apple ID
   - Navigate to Users and Access > Keys (or Integrations > Keys)
   - Click the "+" to create a new key (select "Developer" access)
   - Note the Key ID (e.g., 55TUWU3X1JPV) and download the .p8 file (AuthKey_<KEY_ID>.p8)
   
2) Find your Issuer ID on the same page:
   - On the Keys page, look for "Issuer ID" at the top (a UUID like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
   - Copy it
   
3) Store credentials in keychain:
   ISSUER=
    KEY_ID= KEY_PATH=/Users/mike/Downloads/AuthKey_.p8 \
   scripts/notary-setup.sh
   
   Replace:
   - <issuer-uuid> with the Issuer ID from step 2
   - KEY_ID with your actual key ID
   - KEY_PATH with the actual path to your downloaded .p8 file
   
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
