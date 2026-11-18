# Local packaging and Sparkle staging

Use this guide to test packaging or updater behavior with an isolated
staging identity. Use the [release runbook](RELEASING.md) for stable updates.

## Build an unsigned package

Run `./create_dmg.sh` for the versioned unsigned DMG and checksum under `build/packages/<version>/`. Pass a new output directory to build another copy. The **Package a release** workflow's manual `unsigned` mode builds the same unsigned
package as a downloadable `unsigned-dry-run` Actions artifact. That app has no update
feed or key. It then creates a separate two-version ad-hoc staging pair with a disposable
identity, signs and verifies both feeds and archives, rejects real corruptions, uploads
`staging-integration`, and verifies the downloaded artifacts in an independent job.
The ephemeral identity is staging-only and removed at exit.

```bash
gh workflow run release.yml --ref main -f mode=unsigned
```

The supplemental `unsigned-intel` mode runs the same credential-free jobs on GitHub's
standard `macos-15-intel` runner. It executes the Intel engine natively and reports arm64
runtime execution as skipped; arm64 architecture, hashes and signatures are still checked.
Pair it with native arm64 fixture evidence from the normal mode or a local Mac using
`REQUIRE_BOTH_ENGINE_SLICES=1`. It never selects the production signing runner or relaxes
production verification. [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

```bash
gh workflow run release.yml --ref main -f mode=unsigned-intel
```

For a local repeat, run `scripts/release/staging-smoke.sh build/new-staging-directory`.
The public key is saved in that directory; private exports are excluded from outputs.
Use [production preflight](RELEASING.md#2-run-a-signed-production-preflight) for Developer ID,
notarization and Gatekeeper acceptance.

The Pages staging dispatch modes were used during initial activation. Their
guard requires the production feed to be absent and refuses a published
production Sparkle release. Use the localhost test below for staged updates
now that the production channel exists.

## Check the installed staging update

Use the checksum-pinned tools from `scripts/release/sparkle-tools.sh`. Create
a separate Sparkle identity with `generate_keys --account bettervmaf-staging`
and export it into a private temporary directory. Replace the example paths
with the directory containing the tools and the temporary staging key. Build
both versions with the same localhost feed and staging key.

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
