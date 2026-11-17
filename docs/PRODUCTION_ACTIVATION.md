# Production activation

1. **Renew Apple Developer Program membership** in your Apple account. Do not buy a
   different account or change the bundle identifier. Confirm the team has accepted
   current agreements. Membership renewal itself is a maintainer action.
2. On a trusted Mac, use Xcode → Settings → Accounts → Manage Certificates to create
   a **Developer ID Application** certificate (not Apple Development, Distribution,
   or Developer ID Installer). Export the certificate **and its private key** from
   Keychain Access as a password-protected `.p12`. Record the ten-character Team ID.
   Create an **App Store Connect team API key** with Developer access or an appropriate
   higher role for notarization; record Key ID and Issuer ID and securely retain the
   one-time `.p8` download. Use a team key: this workflow passes `--issuer` to notarytool.
   See [Apple Developer ID](https://developer.apple.com/developer-id/) and
   [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
3. Provision the remaining GitHub settings from this repository checkout. Enter
   passwords/identifiers interactively, without putting their values in shell history:
   ```bash
   gh variable set APPLE_TEAM_ID
   base64 -i /private/path/DeveloperID.p12 | gh secret set APPLE_CERTIFICATE_P12 --env release-signing
   gh secret set APPLE_CERTIFICATE_PASSWORD --env release-signing
   base64 -i /private/path/AuthKey.p8 | gh secret set APPLE_NOTARY_KEY --env release-signing
   gh secret set APPLE_NOTARY_KEY_ID --env release-signing
   gh secret set APPLE_NOTARY_ISSUER_ID --env release-signing
   ```
4. Finish the non-Apple prerequisites **before** readiness is declared:
   - Create and test the stable Sparkle identity and offline backup using the procedure
     in [RELEASING.md](RELEASING.md#trusted-mac-sparkle-setup). This can happen before renewal.
   - Resolve the explicitly open [FFmpeg corresponding-source distribution](ENGINE_PROVENANCE.md#release-readiness-source-audit-2026-11-17).
   - Review and merge the release-readiness PR yourself. The setup agent leaves it unmerged.
   - Run the staging update's install/relaunch acceptance test on an available desktop;
     validate on a physical Intel Mac as well as Apple Silicon before publication.
5. From current reviewed `main`, run the read-only audit, then a genuine signed build:
   ```bash
   python3 scripts/release/readiness.py
   gh workflow run release.yml --ref main -f mode=production-preflight
   ```
   The audit lists missing settings without retrieving secret values. It deliberately
   exits nonzero while the source-distribution prerequisite remains open. Update that
   check only when the prerequisite has actually been resolved. A passing audit checks
   configuration; the workflow proves real signing/notarization. Find the new run in
   Actions or with `gh run list --workflow release.yml`, then inspect its logs and
   download `signed-release` with `gh run download RUN_ID --name signed-release`.
   Preflight creates **no tag, draft, release, or Pages deployment**. Missing credentials
   fail in `credentials`, before CI or packaging. Running production preflight on a
   feature branch fails explicitly; signing environments allow only `main` and `v*`.
6. Check the downloaded DMG on clean Macs: mount, copy to Applications, launch through
   Finder, run the fixture, export a result, and inspect its notarization and Gatekeeper
   checks. The workflow checks the final DMG and mounted app, both staples, exact app
   entitlements, every Sparkle component's team/runtime/timestamp, both pinned helpers,
   EdDSA signatures, version/build, architecture, resources and SHA-256. Real acceptance
   requires genuine credentials; ad-hoc staging cannot establish it. A first production
   update also needs two genuinely Developer ID signed builds using the production key
   on an isolated test channel, to exercise production code-signing policy before release.
7. Choose the first release version after reviewing the existing historical `1.4` draft.
   Do not overwrite it. The current config is `1.4.0`; if `1.4` is published first, choose
   a higher version. Land the version change on `main`, rerun preflight, then follow
   [Version and publish](RELEASING.md#version-and-publish) to create the annotated `vX.Y.Z`
   tag **when you authorize production release work**. Review the generated draft and
   complete assets, source distribution, release notes and clean-Mac acceptance before
   publishing it as stable. A signing failure cannot create a draft; an existing release
   is never overwritten.
8. Publish the reviewed draft manually. Confirm **Deploy stable appcast** succeeds and
   the production URL serves the byte-identical signed `appcast.xml` from the release:
   ```bash
   curl --fail --location https://oliverdougherc.github.io/BetterVMAF/appcast.xml -o /tmp/bettervmaf-published-appcast.xml
   cmp /path/to/downloaded/appcast.xml /tmp/bettervmaf-published-appcast.xml
   ```
   From an older Sparkle-enabled production installation, choose **Check for Updates…**,
   install and relaunch, verify the new version and run the fixture again. Pre-Sparkle
   historical installations require one manual installation. Confirm “up to date” on
   a second check. If publication used `GITHUB_TOKEN`, run `appcast.yml` manually on
   `main` because GitHub suppresses the token's release event.

The credentials are the only Apple-account-dependent setup. The offline backup,
corresponding-source work, PR merge and acceptance tests are separate prerequisites;
renewal alone does not complete them. No production tag or publication is part of the
credential-independent setup pass.
