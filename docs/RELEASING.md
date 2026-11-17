# Releasing BetterVMAF

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
3. Approve **release-signing** in Actions. Verify the draft contains `Better-VMAF-1.4.0.dmg`, its `.sha256` file, and `appcast.xml`. Review the release notes and FFmpeg distribution notices and corresponding source. Test the signed DMG on clean Macs before publication. Publish the complete draft as a stable release when ready.
4. Confirm the **Deploy stable appcast** run passed and the Pages URL serves the signed feed. In an older Sparkle-enabled install, choose **Better VMAF → Check for Updates…**.

The existing `1.4` draft predates this pipeline. Leave it alone unless explicitly authorized. If it is later published, choose a higher version for the first Sparkle-enabled release. Users of older builds install the first Sparkle-enabled version manually from GitHub Releases, then use the app menu or opt into automatic checks at Sparkle’s prompt. Sparkle uses its native download, verification, and installation UI. Checks and downloads can run during comparisons. If a user tries to install and relaunch during a single comparison or batch, Better VMAF defers the restart. Once all comparisons have ended, **Install Downloaded Update** in the app menu resumes the pending installation and relaunches the app. Command-Q during a comparison offers to keep working or stop the FFmpeg workers and quit. A prepared update can install on intentional quit without relaunching the app.

## Stable feed compatibility

Every production Sparkle release must support macOS 15.2 while the stable feed lists a single version. Packaging and mounted-app verification enforce that minimum, so publishing a newer stable build preserves the update path for existing Sparkle users. The pre-Sparkle releases lack verified Sparkle assets and are available through GitHub Releases.

Before raising the macOS minimum, update the pipeline to keep the newest verified immutable release for each supported macOS range in a single EdDSA-signed feed. Verify each retained archive and its declared system requirement, sign the complete feed with the stable key, and test Sparkle’s selection on both sides of the new minimum. [Sparkle minimum system versions](https://sparkle-project.org/documentation/publishing/#minimum-system-version-requirements)

## One-time GitHub setup

- Enable **Release immutability** in repository settings. Restrict creation and changes of `v*` tags to release maintainers using a tag ruleset and keep `main` protected. The workflows require the tag commit to be on `main`.
- Create a **release-signing** environment that permits protected `v*` release tags. Set required reviewers according to the maintainer team’s approval process. Put the signing secrets in this environment.
- In **Settings → Pages**, select **GitHub Actions** as the source. Set up the **github-pages** environment for release tags and manual reconciliation from `main`. Preserve the existing Pages URL if the repository or owner is renamed. This Pages deployment owns the entire project site. [GitHub Pages workflow setup](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- Add repository Actions variables `SPARKLE_PUBLIC_KEY` and `APPLE_TEAM_ID`. The verification job uses both public values to check the published bundle and assets.

### Sparkle signing

The project pins Sparkle 2.10.1 and bundles its license in the app. Download the matching, checksum-pinned Sparkle tools with `scripts/release/sparkle-tools.sh /path/to/new-tools-directory`. Create a dedicated keychain entry on a trusted Mac. Keep the exported key outside the repository with owner-only permissions.

```bash
umask 077
/path/to/tools/bin/generate_keys --account bettervmaf-stable
/path/to/tools/bin/generate_keys --account bettervmaf-stable -p
/path/to/tools/bin/generate_keys --account bettervmaf-stable -x /private/path/bettervmaf-stable.key
gh secret set SPARKLE_PRIVATE_KEY --env release-signing < /private/path/bettervmaf-stable.key
```

Put the printed public key in `SPARKLE_PUBLIC_KEY`. Keep an encrypted offline backup and test recovery with `generate_keys --account <account> -f <private-key-file>` on a trusted Mac. Keep the stable private key out of staging. Preserve both signing identities across normal releases. If you need to rotate them, follow Sparkle’s rotation procedure and validate it on an install that trusts the original identity. If the signing key is lost and the existing installed apps can no longer verify a feed, distribute a manually installed replacement. [Sparkle signing and recovery](https://sparkle-project.org/documentation/#3-segue-for-security-concerns)

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

Run `./create_dmg.sh` for the versioned unsigned DMG and checksum under `build/packages/<version>/`. Pass a new output directory to build another copy. The **Package a release** workflow’s manual run builds the same unsigned package as a downloadable Actions artifact. These builds have no update feed or key.

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
