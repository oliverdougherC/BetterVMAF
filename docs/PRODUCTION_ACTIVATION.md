# Production signing and repository setup

Use this guide to set up or recover the production signing environment on a
trusted Mac. Routine updates start in the [release runbook](RELEASING.md).
Use the same production Sparkle identity for updates to installed copies.

## GitHub configuration

The read-only `scripts/release/readiness.py` checks these settings:

- Pages uses **GitHub Actions** and HTTPS. The stable feed deploys from a published release.
- Release immutability is required for stable publications.
- `main` protection requires strict macOS CI and blocks force pushes and deletion.
- Two active `v*` rulesets restrict creation to repository admins and forbid updates or
  deletion with no bypass on the latter rule. Test these by inspecting effective rules;
  do not create a throwaway production tag.
- **release-signing** and **github-pages** allow only branch `main` and tags `v*`.
  The maintainer reviews the completed draft before publication. The restricted
  refs keep production settings out of feature-branch and fork PR workflows.
- Actions has read-only default token permissions and cannot approve PR reviews. Only
  the draft job requests `contents: write`; only Pages deployment jobs request
  `pages: write` and `id-token: write`. Artifact jobs have read-only source access.

Put public `SPARKLE_PUBLIC_KEY` and `APPLE_TEAM_ID` in repository Actions variables.
Put private signing material only in **release-signing** environment secrets.

## Trusted Mac Sparkle setup

Keep the existing stable Sparkle key for routine updates. For initial setup or
recovery, use a trusted Mac with offline backup storage. The helper
uses Sparkle 2.10.1's checksum-pinned official `generate_keys`, keeps the permanent
identity in the login Keychain, and exports into a private temporary directory
removed at exit. It reuses an existing identity when the account already exists.

On the trusted Mac with `gh` authenticated to this repository, mount your offline backup
volume. Store a strong passphrase separately in your password manager, then run:

```bash
scripts/release/sparkle-identity.sh prepare bettervmaf-stable /Volumes/OFFLINE/BetterVMAF-stable.enc
scripts/release/sparkle-identity.sh recover-test /Volumes/OFFLINE/BetterVMAF-stable.enc /Volumes/OFFLINE/BetterVMAF-stable.enc.public
scripts/release/sparkle-identity.sh provision /Volumes/OFFLINE/BetterVMAF-stable.enc
python3 scripts/release/readiness.py
```

Replace the volume/path before running. OpenSSL prompts directly for the passphrase;
never put it in a command, environment variable, chat or log. The helper encrypts with
AES-256-CBC and salted PBKDF2 (600,000 iterations), decrypts and compares the backup,
then signs a real challenge from the recovered key and verifies it with CryptoKit.
It also proves a modified challenge is rejected. The public key is saved beside the
backup; record its fingerprint separately in your password manager:
`shasum -a 256 /Volumes/OFFLINE/BetterVMAF-stable.enc.public`.
Keep a second encrypted copy on separate offline media and test it with `recover-test`.
Unmount both backup volumes after testing. Never commit an exported key or encrypted
backup. The helper rejects backup paths inside the repository.

`provision` verifies the recovered key against the stable Keychain public key before
uploading `SPARKLE_PRIVATE_KEY` directly to **release-signing**, then setting the repository
`SPARKLE_PUBLIC_KEY`. The private key is never printed or passed as a command argument.
A secret-presence audit cannot verify its value; production packaging repeats the actual
public/private signature check before building.

For disaster recovery on a trusted replacement Mac, first verify the separately
recorded public fingerprint and run `recover-test`. Use the pinned Sparkle tools from
the repository helper, and import only into an absent stable Keychain account:

```bash
set -euo pipefail
umask 077
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
scripts/release/sparkle-tools.sh "$work/tools"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in /Volumes/OFFLINE/BetterVMAF-stable.enc -out "$work/private.key"
"$work/tools/bin/generate_keys" --account bettervmaf-stable -f "$work/private.key"
"$work/tools/bin/generate_keys" --account bettervmaf-stable -p > "$work/public.key"
cmp "$work/public.key" /Volumes/OFFLINE/BetterVMAF-stable.enc.public
scripts/release/sparkle-identity.sh provision /Volumes/OFFLINE/BetterVMAF-stable.enc
rm -rf -- "$work"
trap - EXIT
```

Run these commands in a dedicated shell so its EXIT trap removes the plaintext export
if any step fails. Never replace an existing stable account merely to silence an import
error. Loss or rotation requires [Sparkle's documented key-rotation procedure](https://sparkle-project.org/documentation/#rotating-signing-keys)
and an installed-copy acceptance test. Key loss with required signed feeds may require
a manually installed replacement; do not assume an automatic recovery path.

The helper was tested using a disposable staging account, encrypted backup, separate
recovery, signatures and corruption rejection. No stable private key was generated for
that test. Keep staging keys, bundle IDs and localhost feeds separate from production.
[Official Sparkle key-generation guidance](https://sparkle-project.org/documentation/#3-segue-for-security-concerns).

## Export the Developer ID identity

1. On a trusted Mac, run `security find-identity -v -p codesigning`. Look for a
   valid **Developer ID Application** identity whose Team ID matches the
   `APPLE_TEAM_ID` GitHub Actions variable. This signing identity pairs the
   Apple certificate with its private key.
2. If you need a new identity, create a certificate signing request in
   **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority**. In Apple Developer, choose **Certificates,
   Identifiers & Profiles → Certificates → + → Developer ID → Developer ID
   Application**. Upload the request and install the downloaded certificate on
   the Mac that generated it. [Apple Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
3. In **Xcode → Settings → Accounts**, select your team and open **Manage
   Certificates**. Control-click the Developer ID Application identity, choose
   **Export Certificate**, and save a password-protected `.p12`. You can also
   export from **Keychain Access → login → My Certificates** by selecting the
   certificate and its private key. If `.p12` is unavailable there, check that
   the public certificate and private key appear together in the login keychain,
   or use the Xcode export. [Apple’s signing identity export instructions](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates)

## Provision GitHub signing secrets

From the checkout root on the trusted Mac, replace the example path with the
exported `.p12`. GitHub CLI reads the encoded file from the pipe and prompts
for the export password. Keep the file and password in private storage.

```bash
(
  set -euo pipefail
  repo=oliverdougherC/BetterVMAF
  p12=/private/path/DeveloperID.p12
  test -s "$p12"
  base64 -i "$p12" | gh secret set APPLE_CERTIFICATE_P12 --repo "$repo" --env release-signing
  gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$repo" --env release-signing
  python3 -B scripts/release/readiness.py
)
```

Readiness confirms that the secret names are present. Exercise the identity
with a [signed production preflight](RELEASING.md#2-run-a-signed-production-preflight)
before tagging. The workflow imports the identity into a temporary keychain
and verifies Developer ID signing for the configured team, Apple notarization,
stapling and Gatekeeper.

## Notarization API setup

Set `APPLE_TEAM_ID` in repository Actions variables. Use the 10-character
Team ID from Apple Developer Membership Details.

Open **App Store Connect → Users and Access →
Integrations → App Store Connect API**. Request access if prompted. Generate a
**Team Key** with the **Developer** role, then save its `.p8` file, key ID, and
issuer UUID. The workflow uses team-key authentication with `--issuer`.
[App Store Connect API setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/) ·
[Apple role permissions](https://developer.apple.com/help/account/access/roles/).

Set these secrets in the protected **release-signing** environment.

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Base64-encoded PKCS#12 |
| `APPLE_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `APPLE_NOTARY_KEY` | Base64-encoded App Store Connect `.p8` |
| `APPLE_NOTARY_KEY_ID` | App Store Connect key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer UUID |

Use the GitHub CLI prompts to enter identifiers or passwords and pipe file
contents directly to GitHub for the encoded secrets.

```bash
repo=oliverdougherC/BetterVMAF
gh variable set APPLE_TEAM_ID --repo "$repo"
base64 -i /private/path/AuthKey.p8 | gh secret set APPLE_NOTARY_KEY --repo "$repo" --env release-signing
gh secret set APPLE_NOTARY_KEY_ID --repo "$repo" --env release-signing
gh secret set APPLE_NOTARY_ISSUER_ID --repo "$repo" --env release-signing
```

Authenticate the team key with a read-only `notarytool history` call. Production
preflight verifies the entire signing path using a temporary runner keychain.
The runner submits the app and the final DMG to Apple before applying the Sparkle
EdDSA signatures. Verification requires Developer ID signing from the configured
team, both stapled tickets, and Gatekeeper approval of the mounted app.
[Apple distribution signing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) ·
[Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
