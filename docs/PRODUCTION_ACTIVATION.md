# Activate the first signed release

## Current checkpoint

Apple Developer Program membership is active. The configured Apple team API key
authenticated successfully with `notarytool history`. The Apple Team ID and
notarization secrets are in GitHub. The stable Sparkle public variable matches
the login Keychain key, and the protected private-key secret is present. The
readiness audit also verifies the pinned FFmpeg source and notices.

The remaining GitHub credentials are `APPLE_CERTIFICATE_P12` and
`APPLE_CERTIFICATE_PASSWORD`. Production signing, notarization, and installation
still need a full preflight. See the [release-readiness audit](RELEASE_READINESS.md).

## Export the Developer ID identity

1. On a trusted Mac, locate the **Developer ID Application** identity in **Keychain
   Access → My Certificates**. Confirm it has a private key and belongs to the
   configured Apple Developer team. Import an existing password-protected `.p12`
   if you have a backup of the identity. A certificate downloaded from Apple needs
   the matching private key on the Mac.
2. If you need a new identity, use **Certificate Assistant → Request a Certificate
   From a Certificate Authority** and save the CSR to disk. In Apple Developer,
   open **Certificates, Identifiers & Profiles → Certificates → + → Developer ID
   Application**, upload the CSR, and install the certificate on the Mac that
   created it. Export the identity and private key from **My Certificates** as a
   password-protected `.p12`. [Apple’s Developer ID procedure](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
3. From a trusted Terminal, point to the private export and enter its password at
   the GitHub CLI prompt.

   ```bash
   repo=oliverdougherC/BetterVMAF
   p12=/private/path/DeveloperID.p12
   security find-identity -v -p codesigning
   base64 -i "$p12" | gh secret set APPLE_CERTIFICATE_P12 --repo "$repo" --env release-signing
   gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$repo" --env release-signing
   python3 -B scripts/release/readiness.py
   ```

For fresh Sparkle or Apple API key setup, see the [release runbook](RELEASING.md#github-configuration).

## Verify a signed preflight

Review [PR #8](https://github.com/oliverdougherC/BetterVMAF/pull/8) and approve
the merge. On reviewed `main` with all credential checks passing, dispatch a
production preflight. It produces a signed artifact for review. The separate tag
workflow creates a release draft.

```bash
gh workflow run release.yml --ref main -f mode=production-preflight
gh run list --workflow release.yml --branch main --limit 5
```

On Apple Silicon with Rosetta available, use the checkout for the successful run.
Replace `RUN_ID` with that run’s ID and verify the downloaded artifact.

```bash
run_id=RUN_ID
artifact_dir="$PWD/build/preflight-$run_id"
version=$(python3 scripts/release/release.py version)
dmg=$(python3 scripts/release/release.py asset-name "$version")
gh run download "$run_id" --name signed-release --dir "$artifact_dir"
APPLE_TEAM_ID=$(gh variable get APPLE_TEAM_ID --json value --jq .value)
SPARKLE_PUBLIC_KEY=$(gh variable get SPARKLE_PUBLIC_KEY --json value --jq .value)
export APPLE_TEAM_ID SPARKLE_PUBLIC_KEY
REQUIRE_BOTH_ENGINE_SLICES=1 scripts/release/verify-dmg.sh "$artifact_dir/$dmg" "$version" production
python3 scripts/release/engine_sources.py verify-files "$artifact_dir"
```

The verifier checks the DMG and the mounted app, both staples, Gatekeeper,
sandbox entitlements, nested signatures, architectures, bundled FFmpeg, EdDSA
signatures, and checksums. On clean Apple Silicon and Intel Macs, install from
the downloaded DMG, launch from Finder, run the [24-frame fixture](../Fixtures/)
for a mean near 33.08, and open the exported CSV, JSON, and PDF.

## Approve a draft and verify the live update

1. Keep the signed `1.4.0` preflight app as the update test baseline. The proposed
   first public release is `1.4.1`, build `1004001`, subject to maintainer approval.
   The historical `1.4` draft predates Sparkle. Leave it intact.
2. Land the approved version on `main` and repeat the production preflight. Use
   the [version and tagging procedure](RELEASING.md#version-and-publish) after
   approval. The tag run builds and signs a new copy.
3. Download the draft release assets and repeat DMG and source verification on
   that exact package. Review its release notes, DMG, checksum, signed
   `appcast.xml`, and both FFmpeg ZIPs. Publish the reviewed draft as stable from
   GitHub once final approval is recorded.
4. Confirm **Deploy stable appcast** passes. Download the live feed and compare
   it byte for byte with the appcast from the published release.

   ```bash
   curl --fail --location https://oliverdougherc.github.io/BetterVMAF/appcast.xml \
     -o "$artifact_dir/live-appcast.xml"
   cmp "$artifact_dir/appcast.xml" "$artifact_dir/live-appcast.xml"
   ```

   Set `artifact_dir` to the directory holding the final release assets before
   running the comparison. If publication used `GITHUB_TOKEN`, dispatch
   `appcast.yml` manually from `main` to deploy the verified feed.
5. Launch the retained signed `1.4.0` app and choose **Better VMAF → Check for
   Updates…**. Verify it downloads, installs, and relaunches as the published
   version. Analyze the fixture again and confirm the second update check
   reports that the app is current. Users of pre-Sparkle releases install the
   first signed version once from GitHub Releases.
