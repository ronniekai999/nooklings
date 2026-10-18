#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

: "${DEVELOPER_ID_APPLICATION:?Set your Developer ID Application certificate identity}"
: "${APPLE_TEAM_ID:?Set the Apple team that owns the stable app identity}"
: "${NOTARY_KEYCHAIN_PROFILE:?Store notarytool credentials and set their profile name}"
APP_VERSION="${1:-${APP_VERSION:-1.1.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || [[ "$DEVELOPER_ID_APPLICATION" != 'Developer ID Application:'* ]]; then
  echo "Use a Developer ID Application identity and a 10-character Apple team ID." >&2
  exit 1
fi
export APP_VERSION BUILD_NUMBER
UNIVERSAL=1 ./bundle.sh
swift scripts/verify-bundle.swift Nooklings.app

APP="Nooklings.app"
OUT=".artifacts/releases"
mkdir -p "$OUT"
ZIP="$OUT/Nooklings-${APP_VERSION}-universal.zip"
NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN_PATH:-}" ]]; then NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN_PATH"); fi

# Sign the completed app, with Apple's default designated requirement (identifier
# plus signing team). Do not add debug entitlements or use --deep to mask errors.
codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" \
  --identifier com.ronnie.byte "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --verbose=4 "$APP" 2> "$OUT/signature.txt"
ACTUAL_TEAM="$(sed -n 's/^TeamIdentifier=//p' "$OUT/signature.txt")"
if [[ "$ACTUAL_TEAM" != "$APPLE_TEAM_ID" ]]; then
  echo "Signing team does not match APPLE_TEAM_ID; no app was submitted." >&2
  exit 1
fi
codesign -d -r- "$APP" 2> "$OUT/designated-requirement.txt"
lipo "$APP/Contents/MacOS/Nooklings" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if ! xcrun notarytool submit "$ZIP" "${NOTARY_ARGS[@]}" --wait --timeout 20m \
     --output-format json > "$OUT/notarization.json"; then
  echo "Notarization did not complete. See notarization.json; no distributable artifact was approved." >&2
  exit 1
fi
NOTARY_STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", "Unknown"))' "$OUT/notarization.json")"
if [[ "$NOTARY_STATUS" != Accepted ]]; then
  NOTARY_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$OUT/notarization.json")"
  xcrun notarytool log "$NOTARY_ID" "${NOTARY_ARGS[@]}" "$OUT/notarization-log.json"
  echo "Apple did not accept this build. See notarization-log.json." >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

# Re-create the final download after stapling, so offline installs get the ticket.
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"
printf 'Nooklings %s (%s)\nBundle: com.ronnie.byte\nTeam: %s\nArchitectures: arm64, x86_64\n' \
  "$APP_VERSION" "$BUILD_NUMBER" "$ACTUAL_TEAM" > "$OUT/manifest.txt"
echo "Verified, notarized download: $ZIP"
