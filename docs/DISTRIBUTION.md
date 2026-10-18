# Building and distributing Nooklings

The signing workflow is ready for credentials. **No Developer ID signed or
notarized release has been produced or validated yet.** Apple Developer membership
and a Developer ID Application certificate are required. Ordinary CI builds remain
unsigned development previews.

## Stable identity

Keep these values unchanged across releases:

| Identity | Value |
| --- | --- |
| Bundle ID and designated-requirement identifier | `com.ronnie.byte` |
| Preferences suite | `com.ronnie.byte` |
| Anthropic Keychain service | `com.ronnie.byte.anthropic` |
| ChatGPT Keychain service | `com.ronnie.byte.chatgpt` |
| Data directory | `~/.config/byte` |
| Signing team | The same `APPLE_TEAM_ID` for every release |

Apple's default Developer ID designated requirement binds the identifier to the
signing team. The release script checks that team before submission. Changing the
team or identity can change Keychain access. Moving from an unsigned development
build to the first signed build can still prompt for access; do not promise a
silent migration or delete users' credentials to suppress prompts. The app does
not add new Keychain access groups or sandbox entitlements.

## GitHub Actions setup

Add these repository Actions secrets in **Settings → Secrets and variables → Actions**.
Use a Developer ID **Application** certificate exported with its private key as a
password-protected `.p12`, and an App Store Connect team API key authorized for
notarization. Keep private keys out of the repository and chat.

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | Full certificate identity, `Developer ID Application: … (TEAMID)` |
| `APPLE_TEAM_ID` | Ten-character team ID |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the exported `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Export password |
| `APPLE_API_KEY_P8` | Private `.p8` key, with real line breaks |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER` | App Store Connect issuer ID |

Run **Actions → Signed Mac release → Run workflow**, selecting the reviewed commit's
branch and a numeric version such as `1.1.0`. The workflow:

1. Imports credentials into a temporary, unlocked runner Keychain.
2. Runs native regression tests and builds a universal `arm64` + `x86_64` app.
3. Signs the finished bundle with hardened runtime and a secure timestamp.
4. Verifies signature, team, and architectures; submits the ZIP with `notarytool`.
5. Requires Apple's `Accepted` result, staples and validates the ticket, and runs
   Gatekeeper assessment before rebuilding the downloadable ZIP.
6. Uploads the ZIP, SHA-256 checksum, version manifest, signature requirement, and
   notarization record. Failure uploads diagnostics, never a release ZIP.
7. Deletes the temporary Keychain and private-key files, including on failure.

The workflow produces reviewable artifacts; it does not publish a GitHub release.
After the installed-app checks below pass, attach the verified ZIP and checksum to
the release. Use that stapled ZIP, not the earlier notarization submission archive.
Every build's `CFBundleVersion` is the workflow run number; do not reuse or decrease
it when mixing local and CI releases.

## Local signing

Import your Developer ID Application identity in Keychain Access. Store notarization
credentials once using Apple's `xcrun notarytool store-credentials` interactive flow;
then invoke the script with the stored profile name, not a password in the command:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID1234)'
export APPLE_TEAM_ID='TEAMID1234'
export NOTARY_KEYCHAIN_PROFILE='NooklingsRelease'
export BUILD_NUMBER='100'
./scripts/release.sh 1.1.0
```

For an unsigned universal development build, run `UNIVERSAL=1 ./bundle.sh`.
`APP_VERSION` and `BUILD_NUMBER` can also be supplied to `bundle.sh`; invalid version
strings fail before building.

## Installed-app acceptance checks

Run on a Mac with real credentials before declaring the first signed release ready:

- Download the final ZIP through a browser, expand it, and install in Applications.
  Launch through Finder with normal quarantine/Gatekeeper checks in place.
- Verify all five companions and images load away from the source/build directory.
- Sign into both providers, quit, install a later build signed by the same team,
  and verify accounts, pet histories, archives, settings, and pins survive.
- Exercise Keychain allow/deny/retry, refresh-token rotation, and sign-out. Verify
  migration from a Byte source launch, an unsigned Byte bundle, and Nooklings.
- Enable and disable Launch at login, including while approval is pending, then
  log out/in and verify the installed bundle starts once.
- Complete the [desktop accessibility and display checks](ACCESSIBILITY.md).

Apple references: [Developer ID](https://developer.apple.com/developer-id/),
[distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
and [custom notarization workflows](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
