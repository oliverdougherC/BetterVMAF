# Releasing BetterVMAF

Use this runbook for each stable update. GitHub Releases hosts the immutable
downloads. GitHub Pages serves the signed appcast that tells Sparkle which
version is current. A normal release goes from reviewed `main` through signed
preflight and draft review, then to publication and a live update test.

Use a trusted Mac with Git, Python 3.10 or newer, the GitHub CLI authenticated
to this repository, and a compatible Xcode. Run the examples from the root of
a clean checkout. Use Apple Silicon with Rosetta for independent execution of
both FFmpeg slices. See [signing setup](PRODUCTION_ACTIVATION.md) for
maintainer credentials and [recovery](#recover-a-release-or-feed) for failures.

## Version and publish

### 1. Prepare the version on main

Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
[Config/Version.xcconfig](../Config/Version.xcconfig). Use `MAJOR.MINOR.PATCH`
with canonical decimal components below 1000 and a positive major version.
The build number is
`major * 1000000 + minor * 1000 + patch`, so it sorts in the same order as
the marketing version. Sparkle uses the build number to identify a newer app.
For example, `1.4.2` uses `1004002`.

```bash
python3 -B scripts/release/release.py build-number 1.4.2
```

Merge the reviewed changes and version bump with the required macOS CI check
green. Update the checkout to the reviewed `main` before dispatching preflight.
Write release notes for users upgrading from the last published stable version.

Keep the current stable DMG and a signed installation for the post-publication
update test. Use a separate writable copy of that installation for testing.
Ignored folders ending in `.noindex`, such as `build/release-review.noindex`,
keep retained packages and test apps out of Spotlight.

### 2. Run a signed production preflight

```bash
git switch main &&
  git pull --ff-only origin main &&
  test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" &&
  python3 -B scripts/release/readiness.py &&
  gh workflow run release.yml --ref main -f mode=production-preflight
```

Open the run in Actions and record its ID and commit SHA. Wait for CI and the
`sign` job to pass. The read-only readiness audit checks GitHub configuration
and credential names. The workflow exercises the actual signing credentials.

The preflight builds a universal DMG, signs with Developer ID, notarizes and
staples the app and DMG, and verifies Gatekeeper and both Sparkle EdDSA
signatures. It uploads the five files as `signed-release`, with three days of
retention. Publication and Pages deployment run separately.

Replace `PREFLIGHT_RUN_ID` with the successful production preflight run ID.
Keep these shell variables for the following steps.

```bash
run_id=PREFLIGHT_RUN_ID
version=$(python3 -B scripts/release/release.py version)
tag="v$version"
review_dir="$PWD/build/release-review.noindex/$version"
preflight_dir="$review_dir/preflight-$run_id"
gh run download "$run_id" --name signed-release --dir "$preflight_dir" &&
  package_dir="$preflight_dir"
```

#### Verify a downloaded production package

Use this check for the preflight artifact and again for the exact draft assets.
Set `package_dir` to the absolute directory holding the five files.

```bash
(
  set -euo pipefail
  dmg=$(python3 -B scripts/release/release.py asset-name "$version")
  export APPLE_TEAM_ID SPARKLE_PUBLIC_KEY
  APPLE_TEAM_ID=$(gh variable get APPLE_TEAM_ID --json value --jq .value)
  SPARKLE_PUBLIC_KEY=$(gh variable get SPARKLE_PUBLIC_KEY --json value --jq .value)
  REQUIRE_BOTH_ENGINE_SLICES=1 scripts/release/verify-dmg.sh "$package_dir/$dmg" "$version" production
  python3 -B scripts/release/engine_sources.py verify-files "$package_dir"
  (cd "$package_dir" && shasum -a 256 "$dmg" "$dmg.sha256" appcast.xml ./*.zip)
)
```

Expect the versioned DMG, its `.sha256`, `appcast.xml`, and the corresponding
source and notices ZIPs in [the engine source lock](../Config/EngineSources.json).
Verify that the app, DMG name and appcast agree on the release version.
The mounted app check covers its sandbox, nested signatures, framework
architectures, model and license resources, and both engine slices.
Keep both ZIPs alongside the DMG. [Engine provenance](ENGINE_PROVENANCE.md)

Install a copy from the downloaded DMG and launch it from Finder. Select
[`vmaf-reference.mp4`](../Fixtures/vmaf-reference.mp4) and
[`vmaf-comparison.mp4`](../Fixtures/vmaf-comparison.mp4) through the app's
Open panels. Expect 24 scored frames and a mean near **33.08** on Apple Silicon.
Save CSV, JSON and PDF through the app. Check the frame count and score in CSV
and JSON, and open the PDF to inspect the summary, heat map and frame table.
Record the macOS version and architecture tested. Run installed-app acceptance
on clean Apple Silicon and Intel Macs where available and record any coverage gap.
Distinguish Intel helper execution under Rosetta from an installed-app test on
native Intel hardware.

### 3. Approve and push the release tag

Review the preflight result, exact commit and installed-app evidence with the
maintainer before creating the tag. A repository admin pushes the protected
`v*` tag. The tag stays on the tested commit for the life of the release.

The following checks require a successful `signed-release` artifact from the
manual run on `main`, and require the checkout and current remote `main` to
match that run. Use the production preflight `run_id` and the reviewed `tag`
from step 2. If `main` has advanced, preflight the new release commit.

```bash
(
  set -euo pipefail
  preflight_sha=$(gh run view "$run_id" --json conclusion,event,headBranch,headSha \
    --jq 'select(.conclusion == "success" and .event == "workflow_dispatch" and .headBranch == "main").headSha')
  signed_artifact=$(gh api "repos/{owner}/{repo}/actions/runs/$run_id/artifacts" \
    --jq '.artifacts[] | select(.name == "signed-release" and .expired == false) | .id')
  test -n "$preflight_sha" && test -n "$signed_artifact" || exit 1
  git fetch origin main
  test "$(git rev-parse origin/main)" = "$preflight_sha"
  test "$(git rev-parse HEAD)" = "$preflight_sha"
  test "$tag" = "v$(python3 -B scripts/release/release.py version)"
  git tag -a "$tag" "$preflight_sha" -m "Better VMAF $version"
  git push origin "refs/tags/$tag"
)
```

### 4. Verify the release draft and approve publication

Watch the tag-triggered [Package a release workflow](../.github/workflows/release.yml).
It reruns CI, builds and signs a fresh package, and attaches the five files to a
GitHub draft. The tag build has its own signatures and checksums.

```bash
draft_dir="$review_dir/draft"
gh release download "$tag" --pattern '*' --dir "$draft_dir" &&
  package_dir="$draft_dir" &&
  gh release view "$tag" --json tagName,isDraft,isPrerelease,assets
```

Match the five downloaded files to the draft's asset digests and repeat
[production package verification](#verify-a-downloaded-production-package),
including installation, fixture analysis and exports from this DMG. Confirm the
draft is for the intended tag and includes the reviewed release notes and links
to the FFmpeg source and notices. Get separate maintainer approval to publish
the verified draft as a stable release.

### 5. Publish, deploy and test the live update

After publication approval, publish the draft as the latest stable release in
GitHub Releases or use the GitHub CLI.

```bash
gh release edit "$tag" --draft=false --prerelease=false --latest=true &&
  gh release view "$tag" --json isDraft,isPrerelease,isImmutable,assets
```

Confirm the release is public, stable and immutable, and that its asset digests
match the verified draft. Publication triggers
[Deploy stable appcast](../.github/workflows/appcast.yml). That workflow verifies
the highest published stable version and deploys its signed appcast. The previous
live feed continues serving while a new package is still a draft.

Wait for the Pages deployment to succeed. Compare the public feed against the
release asset and verify its EdDSA signature and the referenced DMG signature.

```bash
(
  set -euo pipefail
  live_feed="$review_dir/live-appcast.xml"
  feed_url=$(python3 -B scripts/release/release.py stable-feed)
  curl --fail --silent --show-error --location "$feed_url" --output "$live_feed"
  cmp "$live_feed" "$draft_dir/appcast.xml"
  export SPARKLE_PUBLIC_KEY
  SPARKLE_PUBLIC_KEY=$(gh variable get SPARKLE_PUBLIC_KEY --json value --jq .value)
  dmg=$(python3 -B scripts/release/release.py asset-name "$version")
  python3 -B scripts/release/release.py verify-feed "$live_feed" "$draft_dir/$dmg" "$version" stable
)
```

Quit other BetterVMAF instances and open the writable copy of the previous
stable installation. Confirm its starting version in **About Better VMAF**.
Choose **Better VMAF → Check for Updates…**, then **Install Update** and
**Install and Relaunch**. Confirm the new version and build in About, analyze
the fixture, and run **Check for Updates…** again. Expect **You’re up to date!**

Record the tag, commit, workflow links, final file digests, signing and
notarization results, and installed-app outcomes. Include outstanding hardware
or test coverage. Keep the published asset checksums with the release record.
See the [1.4.1 activation record](RELEASE_READINESS.md#first-production-release)
for a completed example.

Users on 1.4.1 and later can update from the app menu or opt into automatic
updates. Users upgrading from a pre-Sparkle version install the latest signed
DMG from GitHub once. During a comparison, BetterVMAF defers the update restart.
When comparisons finish, **Install Downloaded Update** resumes installation.

## Stable feed compatibility

Keep the production bundle identifier, Sparkle key and feed URL stable across
routine releases. Every production release must support macOS 15.2 while the
stable feed lists a single version. Packaging and mounted-app verification
enforce that minimum so existing Sparkle users can receive newer builds.

Before raising the macOS minimum, update the pipeline to keep the newest verified immutable release for each supported macOS range in a single EdDSA-signed feed. Verify each retained archive and its declared system requirement, sign the complete feed with the stable key, and test Sparkle’s selection on both sides of the new minimum. [Sparkle minimum system versions](https://sparkle-project.org/documentation/publishing/#minimum-system-version-requirements)

## GitHub configuration

See [production signing and repository setup](PRODUCTION_ACTIVATION.md) for
the required GitHub settings, Developer ID, notarization and Sparkle key
recovery. Run the read-only readiness audit to check live configuration.

## Local packaging and staging

See [local packaging and Sparkle staging](RELEASE_STAGING.md) for unsigned
DMGs, credential-free Actions runs and localhost acceptance tests.

## Recover a release or feed

- **A hosted job never started.** Check the Actions annotations for runner
  acquisition or capacity errors. Retry the failed job on the same commit or
  tag. Recorded success must include the actual CI and signing jobs.
- **Preflight signing fails.** Run the [readiness audit](../scripts/release/readiness.py)
  and inspect the failing step. Check the matching Developer ID private key,
  team identity, notarization key and stable Sparkle key as applicable.
  Rerun production preflight after the fix.
- **Tag packaging or draft upload fails.** Retry a transient failure on the
  same protected tag. If an incomplete draft exists, review it with the maintainer
  before removing that draft and rerunning its tag. The workflow refuses an
  existing release record. A source or workflow fix after tagging requires a
  reviewed commit and a higher version.
- **Publication succeeded and the Pages run is missing or failed.** Inspect
  the production run. Retry a transient job failure or dispatch the same stable
  verifier from `main`. A publication made with the Actions `GITHUB_TOKEN` needs
  a manual dispatch because GitHub suppresses the release event it would trigger.
  [GitHub workflow events](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

  ```bash
  gh workflow run appcast.yml --ref main
  ```

- **Sparkle reports an error retrieving updates.** Fetch the [production
  appcast](https://oliverdougherc.github.io/BetterVMAF/appcast.xml). Before the
  first publication, a missing feed can explain this error in a draft build.
  For an established channel, check that Pages deployed the intended release,
  the feed is reachable over HTTPS, and its published bytes and signatures
  verify. If the feed verifies and Sparkle offers no update, check the installed
  build number against the feed and test from the previous stable version.
- **A published version has a defect.** Ship a fixed build with a higher
  version through the same gates. Keep the immutable release and tag as the
  record of what shipped. [GitHub immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
