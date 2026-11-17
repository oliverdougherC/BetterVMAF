# Releasing BetterVMAF

Start with the [current readiness audit](RELEASE_READINESS.md) and the concise
[production activation checklist](PRODUCTION_ACTIVATION.md). Run
`python3 scripts/release/readiness.py` for a read-only check of live GitHub settings
and missing credential names. A configuration check does not validate Apple credentials.

The package workflow runs shared macOS CI, creates a universal DMG, and verifies the app mounted from the final image. Production builds sign the app and Sparkle components with Developer ID, preserve the pinned FFmpeg signatures, and notarize and staple the app and image. Sparkle signs the finished DMG and appcast with EdDSA. The workflow opens a GitHub draft only after these checks pass.

A maintainer publishes the draft in GitHub. The publication event validates the highest published stable version, then deploys its signed appcast to [GitHub Pages](https://oliverdougherc.github.io/BetterVMAF/appcast.xml). The authenticated Pages deployment serves only the feed. Its DMG stays in GitHub Releases. The manual **Deploy stable appcast** workflow on `main` reruns the same checks, including when publishing through automation that uses `GITHUB_TOKEN`. GitHub suppresses the release event for that token. [GitHub workflow events](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

## Version and publish

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in [Config/Version.xcconfig](../Config/Version.xcconfig). Use `MAJOR.MINOR.PATCH` with canonical decimal components below 1000. The build number is `major * 1000000 + minor * 1000 + patch` so both versions sort in the same order. For example, `1.4.0` uses `1004000`. `python3 scripts/release/release.py build-number 1.4.0` computes it.
2. Land the version bump on `main`. After the setup below, create and push the corresponding annotated tag on that reviewed commit. For version 1.4.0, run the commands below.
   ```bash
   git fetch origin main
   git tag -a v1.4.0 origin/main -m 'Better VMAF 1.4.0'
   git push origin refs/tags/v1.4.0
   ```
3. Inspect the **release-signing** run in Actions. Verify the draft contains `Better-VMAF-1.4.0.dmg`, its `.sha256` file, and `appcast.xml`. Review the release notes and FFmpeg distribution notices and corresponding source. Test the signed DMG on clean Macs before publication. Publish the complete draft as a stable release when ready.
4. Confirm the **Deploy stable appcast** run passed and the Pages URL serves the signed feed. In an older Sparkle-enabled install, choose **Better VMAF → Check for Updates…**.

The existing `1.4` draft predates this pipeline. Leave it alone unless explicitly authorized. If it is later published, choose a higher version for the first Sparkle-enabled release. Users of older builds install the first Sparkle-enabled version manually from GitHub Releases, then use the app menu or opt into automatic checks at Sparkle’s prompt. Sparkle uses its native download, verification, and installation UI. Checks and downloads can run during comparisons. If a user tries to install and relaunch during a single comparison or batch, Better VMAF defers the restart. Once all comparisons have ended, **Install Downloaded Update** in the app menu resumes the pending installation and relaunches the app. Command-Q during a comparison offers to keep working or stop the FFmpeg workers and quit. A prepared update can install on intentional quit without relaunching the app.

## Stable feed compatibility

Every production Sparkle release must support macOS 15.2 while the stable feed lists a single version. Packaging and mounted-app verification enforce that minimum, so publishing a newer stable build preserves the update path for existing Sparkle users. The pre-Sparkle releases lack verified Sparkle assets and are available through GitHub Releases.

Before raising the macOS minimum, update the pipeline to keep the newest verified immutable release for each supported macOS range in a single EdDSA-signed feed. Verify each retained archive and its declared system requirement, sign the complete feed with the stable key, and test Sparkle’s selection on both sides of the new minimum. [Sparkle minimum system versions](https://sparkle-project.org/documentation/publishing/#minimum-system-version-requirements)

## GitHub configuration

Configured on 2026-11-17, and inspected by `scripts/release/readiness.py`:

- Pages source is **GitHub Actions**, HTTPS enabled. Enabling the site does not publish
  `appcast.xml`. The isolated smoke workflow uses only `/staging/release-readiness/`.
- Release immutability is enabled for future publications. Historical releases and the
  existing `1.4` draft were not modified.
- Existing `main` protection retains the strict macOS CI check and blocks force pushes
  and deletion. Its existing admin bypass policy is preserved.
- Two active `v*` rulesets restrict creation to repository admins and forbid updates or
  deletion with no bypass on the latter rule. Test these by inspecting effective rules;
  do not create a throwaway production tag.
- **release-signing** and **github-pages** allow only branch `main` and tags `v*`.
  No reviewer or wait timer is required for this single-maintainer repository; publishing
  the completed draft remains the manual release gate. Feature branches cannot access
  these environments. Fork PR workflows receive no release secrets.
- Actions has read-only default token permissions and cannot approve PR reviews. Only
  the draft job requests `contents: write`; only Pages deployment jobs request
  `pages: write` and `id-token: write`. Artifact jobs have read-only source access.

Put public `SPARKLE_PUBLIC_KEY` and `APPLE_TEAM_ID` in repository Actions variables.
Put private signing material only in **release-signing** environment secrets.

### Trusted Mac Sparkle setup

This does **not** require Apple membership. The stable identity is not yet created or
provisioned: the maintainer must choose offline storage and a passphrase. Do not generate
it in Actions. The helper uses Sparkle 2.10.1's checksum-pinned official `generate_keys`,
keeps the permanent identity in your login Keychain, and exports only into a private
short-lived directory removed at exit. Existing accounts are reused rather than rotated.

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

### Developer ID and notarization

When membership is available, export a **Developer ID Application** identity with its private key as a password-protected PKCS#12. Create an App Store Connect team API key with access to notarization. Set these **release-signing** environment secrets:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Base64-encoded PKCS#12 |
| `APPLE_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `APPLE_NOTARY_KEY` | Base64-encoded App Store Connect `.p8` |
| `APPLE_NOTARY_KEY_ID` | App Store Connect key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer UUID |

Use `base64 -i /private/path/file | gh secret set <NAME> --env release-signing` to load the binary files. The runner uses a temporary keychain and deletes it at exit. Both the app and the final DMG must pass Apple notarization before EdDSA signing. Verification requires an Apple-issued Developer ID Application signature from the configured team, both stapled tickets, and Gatekeeper approval of the mounted app. With credentials absent, the production workflow cannot create a draft. [Apple distribution signing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) · [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## Local packaging and staging

Run `./create_dmg.sh` for the versioned unsigned DMG and checksum under `build/packages/<version>/`. Pass a new output directory to build another copy. The **Package a release** workflow's manual `unsigned` mode builds the same unsigned
package as a downloadable `unsigned-dry-run` Actions artifact. That app has no update
feed or key. It then creates a separate two-version ad-hoc staging pair with a disposable
identity, signs and verifies both feeds and archives, rejects real corruptions, uploads
`staging-integration`, and verifies the downloaded artifacts in an independent job.
The ephemeral identity is staging-only and removed at exit.

```bash
gh workflow run release.yml --ref main -f mode=unsigned
```

For a local repeat, run `scripts/release/staging-smoke.sh build/new-staging-directory`.
The public key is saved in that directory; private exports are excluded from outputs.
For a genuine Apple preflight, select `production-preflight` on reviewed `main`. It checks
credentials before CI and produces `signed-release` without a tag, draft, publication or
feed deployment. See the activation checklist for clean-Mac acceptance.

The **Deploy stable appcast** workflow accepts an optional `staging_package_run_id`
for an isolated Pages smoke test using a successful unsigned package run ID. It verifies the transferred staging DMG and publishes only the signed
staging appcast/public key under `/staging/release-readiness/`, with localhost archive URLs.
This is a transport/permissions test, not a remotely installable update channel. It uses
a separate `github-pages-staging` environment, serializes with production deployments,
requires the production URL to be 404 and refuses any published production Sparkle release.
After first production publication it must stay disabled. It does not publish the root
`appcast.xml`, deploy a DMG, or read stable signing secrets.

For an end-to-end run on a Mac, create a second Sparkle key with `generate_keys --account bettervmaf-staging`, then export it to a private temporary directory as above. Build two versions with the same localhost feed and staging key.

```bash
export SPARKLE_FEED_URL=http://localhost:18742/appcast.xml
export SPARKLE_PUBLIC_KEY="$(/path/to/tools/bin/generate_keys --account bettervmaf-staging -p)"
export SPARKLE_TOOLS_DIR=/path/to/tools/bin
export SPARKLE_PRIVATE_KEY="$(cat /private/path/bettervmaf-staging.key)"
scripts/release/package.sh staging build/staging-old 1.4.0
scripts/release/package.sh staging build/staging-new 1.4.1
unset SPARKLE_PRIVATE_KEY
python3 -m http.server 18742 --bind 127.0.0.1 --directory build/staging-new
```

Install the older app by copying it out of the mounted DMG to a writable scratch directory. Open that copy and choose **Check for Updates…**. Choose **Install Update**, then **Install and Relaunch**. Verify that the same copy relaunches as `1.4.1`, then check again for the already-current dialog. Staging is ad-hoc signed, uses `neurophasia.BetterVMAF.Staging`, and accepts a loopback-only feed. Keep the staging and stable app copies in different directories.

For negative cases, start with a fresh copy of the older app. Stop the server to test a network failure. Serve a malformed or edited `appcast.xml` to test feed rejection. To test archive rejection, keep the appcast and its declared DMG length unchanged and modify a byte of the served DMG. Restore pristine staging artifacts between cases.

Use the installed copy to select both pinned files in `Fixtures/` through the Open panels and verify a 24-frame mean VMAF near 33.08. Run a two-item batch and save CSV, JSON, and PDF through the Save panel to a directory outside the container. Run the fixture again after Sparkle relaunches the updated copy.

During a long comparison, choose **Check for Updates…**, finish downloading the update, then choose **Install and Relaunch** while FFmpeg is still running. Verify that the app and FFmpeg stay alive and that the installed bundle still reports version `1.4.0`. Press Command-Q, choose **Keep Comparing**, and confirm the job continues. Once the comparison finishes, verify the app stays open on `1.4.0` until you choose **Install Downloaded Update**. Verify that it relaunches as `1.4.1`. Repeat with a batch and cancel it before choosing **Install Downloaded Update**.

From a fresh copy of `1.4.0`, repeat the download during analysis and leave Sparkle at **Ready to Install**. Press Command-Q, choose **Keep Comparing**, and confirm that the installed version and processes are unchanged. Press Command-Q again and confirm **Quit**. Verify that the FFmpeg child and the app exit, the bundle becomes `1.4.1`, and the app stays closed. Repeat with a deferred **Install and Relaunch** request in batch mode.

Run a fixture on physical Apple Silicon and Intel Macs before the first production publication. The package verifier checks both architectures and runs both FFmpeg slices when a native host or Rosetta is available. Local ad-hoc testing does not establish Developer ID, notarization, Gatekeeper, or native Intel acceptance.

## Recover a release or feed

- If a build or notarization fails, correct the cause and rerun the tag workflow. A partially uploaded draft stays outside the update feed. Review and remove that incomplete draft before rerunning its tag. The workflow refuses to overwrite an existing release.
- If publication succeeded but the feed deploy failed, fix Pages settings or transient verification failures and run **Deploy stable appcast** on `main`. It recomputes the highest published stable version and refuses incomplete, mutable, or unverifiable assets.
- For a defective published version, publish a fixed build with a higher version. Published immutable assets cannot be replaced. If updates must stop immediately, unpublish the Pages site while the fix is prepared and prevent the defective release from being selected again. Mark it as a prerelease or remove the release after reviewing the consequences. A subsequent deploy selects the highest remaining eligible version. Already-updated copies require a newer fix or a manual reinstall.
