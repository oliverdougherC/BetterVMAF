# Release-readiness audit and first production release

## First production release

BetterVMAF **1.4.1 (1004001)** shipped on **2026-11-18** from
`2de216bf110fec0db409e63fe1c7425c3289c7e9`. Follow the
[release runbook](RELEASING.md#version-and-publish) for subsequent updates.

| Check | Evidence |
| --- | --- |
| macOS CI on the release commit | [44373318332](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44373318332) |
| Signed 1.4.0 baseline | [44365159635, attempt 2](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44365159635/attempts/2) |
| Signed 1.4.1 preflight | [44386401884](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44386401884) |
| Signed tag build and draft | [44391377539](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44391377539) |
| Immutable publication | [v1.4.1](https://github.com/oliverdougherC/BetterVMAF/releases/tag/v1.4.1) |
| Verified production Pages deployment | [44399561506](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44399561506) |

The exact draft DMG and mounted app passed Developer ID, Apple notarization,
staple and Gatekeeper checks. The signed appcast on Pages matched the release
asset byte for byte, and the feed and DMG EdDSA signatures verified. The FFmpeg
corresponding source and notices matched the pinned engine source lock.

On Apple Silicon, the installed sandboxed app scored **33.08 over 24 frames**.
CSV, JSON and the rendered PDF matched the 1.4.0 baseline. Sparkle installed
the public 1.4.1 update from the retained signed 1.4.0 app and relaunched it.
The updated app analyzed the fixture again, and a second update check reported
that it was up to date. The Intel engine also passed under Rosetta at **33.09**.
Native Intel installed-app acceptance remained outstanding.

Published SHA-256 digests for the five attached assets

```text
583dba6689c2357e00ffab71b7d3bcc430dc13a9aabc69ec3975f0fc3f0385d5  Better-VMAF-1.4.1.dmg
47bd909d3a84da23ecec105e3ea6cae8cd2669ce76ef9b8700360001e8327e79  Better-VMAF-1.4.1.dmg.sha256
16a8a0a7d0b867e9118b8b4f288d6335a0c1b49722dd3f8f635bca4b2e400880  appcast.xml
963b0ec72f3f8db9ea7a5588221ee78ab227e1c19b7255ec53dee497f8c55bff  ffmpeg-9.0.2-macos-notices.zip
00583f1540ec1b415c7db16040e12ecdcb5a0d6f44a499ac0dd37135835d3f10  ffmpeg-9.0.2-macos-sources.zip
```

## Original audit from 2026-11-17

The following snapshot records the state before production activation.
Pending items and local build paths refer to that checkpoint.

This audit starts from merged PR #7, `main` commit
`d0ec9e5d77d8653f35130b7f28a2ad3adc62a4bc`. The release changes are in
[PR #8](https://github.com/oliverdougherC/BetterVMAF/pull/8) for review.
At that checkpoint the remaining work was to provision the Developer ID
identity and run the signed preflight, draft review and live update test.

## Prerequisites

| Prerequisite | Classification | Evidence / remaining action |
| --- | --- | --- |
| Universal app, pinned Sparkle 2.10.1, bundled arm64/Intel engines | Complete | Real local packages; both engine fixtures execute; code/resources verified from final mounted DMGs. |
| Pages Actions source, HTTPS | Configured now | Live Pages API reports `build_type=workflow`, HTTPS enabled. Production `/appcast.xml` remains 404. |
| Release immutability | Configured now | Live API reports enabled. Existing historical releases and `1.4` draft remain untouched. |
| Protected `main` | Already present; preserved | Strict macOS CI required; force pushes/deletion prohibited. Existing admin bypass policy unchanged. |
| Protected `v*` tags | Configured now | Separate active creation rule (repository admins only) and update/deletion rule (no bypass). No tag created to test them. |
| `release-signing`, `github-pages` | Configured now | Custom policies allow only branch `main` and tags `v*`. No redundant reviewer/wait gate for a solo maintainer. |
| Actions permissions | Already safe; preserved | Read-only default token; no PR approval. Job-scoped draft write, Pages write and OIDC only. Actions are pinned by commit. |
| Stable Sparkle identity and GitHub key settings | Provisioned | The maintainer ran the encrypted recovery and provisioning setup. The GitHub public key matches the stable Keychain identity. The protected private-key secret is present. Preflight verifies the uploaded private key with a signature challenge. |
| Staging identity, signed appcast and archive rejection tests | Complete locally | Disposable identity only; actual pinned Sparkle signing tools plus independent CryptoKit verification. Private key exports excluded from artifacts and removed at exit. |
| Staging install/relaunch | Complete on this Apple Silicon Mac | Installed 1.4.0 → 1.4.1 through Sparkle; About showed 1.4.1 (1004001), second check said current; external fixture scored 33.08 after relaunch. |
| Clean production-Mac acceptance | Pending | Native Intel fixture execution passed in hosted staging. Install and test the signed production DMG on Apple Silicon and Intel Macs during acceptance. |
| FFmpeg corresponding source and linked-library notices | Verified and pinned | Verified the portable-ffmpeg source reconstruction for both binary hashes. Production preflight stages both archives. Tag packaging attaches them to the draft, and Pages checks their published digests. See ENGINE_PROVENANCE.md. |
| Apple membership, Team ID and notarization team API key | Provisioned | Membership confirmed active. Apple accepted a read-only `notarytool history` request. The team variable and all three protected notarization secrets are present. |
| Developer ID Application identity and export password | **Missing** | Provide `APPLE_CERTIFICATE_P12` and `APPLE_CERTIFICATE_PASSWORD` in `release-signing`. |
| Production signing, notarization, stapling, Gatekeeper and Sparkle update | Pending | Run preflight on reviewed `main` with the Developer ID identity. Verify the exact draft and run an installed-app update against the production feed after publication. |
| Production release and feed | Intentionally inactive | A maintainer reviews and publishes a complete immutable draft only after activation checks. |

`python3 scripts/release/readiness.py` re-inspects the live GitHub settings, public
variable formats and environment secret **names**, never secret values. It exits
nonzero for missing settings, inaccessible APIs or discrepancies in pinned FFmpeg
helpers and source assets. Production preflight exercises the credentials loaded
from GitHub.

## Corrections

- The original manual workflow reported success while its unsigned package job was
  skipped because a transitive tag-validation dependency was skipped. Explicit status
  conditions now run the manual path and still allow cancellation. Original run:
  [44150855882](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44150855882).
- Production inputs are checked together before CI, and missing names are listed
  without values. Manual `production-preflight` runs only on reviewed `main`, produces
  signed artifacts, and cannot create a tag/draft or deploy a feed. Feature-branch
  production dispatch fails explicitly instead of silently skipping all jobs.
- Credentials are removed from subprocess environments before metadata/build tools
  start. Sparkle public/private correspondence is proved with a real signature before
  building. Temporary signing keychains extend and restore the original search list;
  traps delete the keychain, certificate/key files and scratch output on exit/signals.
- Signing proceeds inside out through Sparkle helpers/XPCs, framework and app, preserving
  helper entitlements and the app's exact sandbox entitlements. Pinned FFmpeg signatures
  and hashes remain intact. Production verification additionally requires each Sparkle
  component and app to satisfy the expected Developer ID team requirement and report
  hardened runtime and a secure timestamp. Both app and DMG retain notarization/staple
  checks; app Gatekeeper approval is required before draft creation.
- Unsigned dispatch now also exercises a disposable staging pair, real signed XML and
  archive validation, edited/malformed feed, same-length archive edit and wrong-key
  rejection. A separate download job verifies the transferred artifacts independently.
- Pinned actionlint checks workflow syntax and expressions in CI alongside shell
  and plist checks and the release test suite. Package verification checks the
  bundled notices.
- Pages smoke testing is separately scoped and serialized with production, refuses an
  existing live production channel/release, and emits only staging-path data. The
  production feed deploy still selects the highest complete immutable stable release
  and verifies final signatures/notarization before upload/deployment.

## Local evidence

macOS execution was available: Apple Silicon, Xcode 27.2 locally; hosted CI uses the
repository's documented Xcode 16.4 and shared VMAF scheme. Local output is ignored under
`build/`; exported private keys and encrypted test backups are not committed.

- Final unsigned DMG: `build/readiness-final-unsigned`, mounted metadata/version/build,
  architectures, model/license resources, Applications symlink and SHA-256 verified.
- Two-version signed staging pair: `build/readiness-final-staging`. Pinned official
  sign_update verifies the signed feed; independent CryptoKit checks both signatures.
  Real corruption/identity rejection checks pass. The identity is disposable and removed. A stopped staging server also produced the expected Sparkle Update Error dialog.
- Both packaged engines retain exact SHA-256 and Developer ID signatures. Fixture:
  24 frames, libvmaf 3.2.0; arm64 mean 33.08, x86_64 via Rosetta mean 33.09.
- Separate installed staging pair: `build/readiness-ui/Better VMAF.app` updated through
  Sparkle's real user interface to 1.4.1 and analyzed externally selected fixtures.
- Encrypted-backup helper exercised with a disposable Keychain account. Creation,
  decrypt/compare, actual recovered-key signing, independent verification, changed-byte
  rejection and a separate recovery invocation passed. Test account/backups removed.
- `python3 -B -m unittest discover -s scripts/release -p 'test_*.py'`: 18 passing tests,
  including actual missing-credential package rejection before xcodebuild/output and
  exclusion of credential values from child environments. Existing publication tests
  reject incomplete/mutable assets and wrong metadata; real signature tests reject
  changed bytes. Shell/plist lint, actionlint and `git diff --check` pass.

## Hosted integration evidence

- [PR macOS CI, 44157102127](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44157102127): passed the shared scheme's build/unit/UI/engine tests, 15 release tests and pinned workflow lint on Xcode 16.4.
- [Unsigned package job, 44152000881](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44152000881): actually built/mounted the DMG, ran both engines at 33.08/33.09 and uploaded the 69 MB unsigned artifact. This exploratory run was later cancelled before its staging job obtained a runner; it is not a complete successful workflow run.
- [Production feature-branch rejection, 44154134242](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44154134242): failed explicitly at dispatch-policy, with signing/draft/deployment skipped.
- [Pages transport, 44157089952](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44157089952): passed real EdDSA verification on Linux, Pages artifact upload and authenticated deployment through github-pages-staging. The public staging feed and public key were fetched and compared byte-for-byte with the verified input; CryptoKit independently verified the downloaded feed. Root production appcast.xml returned HTTP 404 after deployment. Logs confirm prepare has read-only Contents/Actions and deploy has only Pages write plus OIDC. The temporary feature-branch deployment policy was removed after the test; staging deployment now allows only main.
- [ARM hosted retry, 44154827381](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44154827381): GitHub failed runner acquisition after 15 minutes, explicitly reporting macOS arm64 capacity constraints. This is not a code/test failure. A subsequent ARM attempt was superseded by the explicit native Intel run. The default and production runner choices remain unchanged.

- [Complete unsigned Intel pipeline, 44158538459](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44158538459): **passed** shared CI, unsigned DMG packaging/upload, real two-version staging signing/corruption tests/upload, and independent download/mounted verification of both transferred staging DMGs. Intel FFmpeg executed natively. ARM runtime execution is explicitly skipped on Intel, while its architecture/hash/signature remain required. No signing environment, production tag, draft or production feed deployment was involved.
- Downloaded that run's unsigned artifact and newer staging DMG were independently mounted and verified on this Apple Silicon Mac with REQUIRE_BOTH_ENGINE_SLICES=1: native arm64 33.08 and x86_64 under Rosetta 33.09. All metadata, model/license resources, code-signature checks, checksums, and staging EdDSA signatures passed.
- Installed the older hosted staging DMG's app into build/readiness-hosted-ui, served the newer hosted artifacts on loopback, then performed Sparkle's actual download/install/relaunch. About showed 1.4.1 (1004001), the second check reported current, and the external fixture scored 33.08 after relaunch. The test server was stopped after acceptance.
- [Default ARM PR CI, 44158550848](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44158550848): **passed** on the same code revision as the complete Intel pipeline. Both architectures therefore have real execution evidence; the Intel option supplements the unchanged default/production path.
- [Required macOS CI, 44213702208](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44213702208): **passed** on the revision that adds and tests the pinned source and notices release assets. Earlier [runner acquisition failure](https://github.com/oliverdougherC/BetterVMAF/actions/runs/44161968427) completed without assignment or execution.

Cancelled or capacity-failed exploratory runs are not counted as full-pipeline successes.

GitHub administrators can still manually create or publish releases outside these
workflows. The automated draft path requires successful signed/notarized packaging;
the feed deploy independently refuses incomplete, mutable or unverifiable releases.
The unchanged historical 1.4 draft is not a Sparkle release candidate.

## Activation plan at this checkpoint

The plan was to provision the Developer ID identity, pass signed preflight on
`main`, and retain the signed 1.4.0 app to test the first public update to
1.4.1. See the [first production release](#first-production-release) for the
results.
