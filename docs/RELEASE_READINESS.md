# Release-readiness audit — 2026-11-17

This audit starts from merged PR #7, `main` commit
`d0ec9e5d77d8653f35130b7f28a2ad3adc62a4bc`. Corrections are proposed in
[PR #8](https://github.com/oliverdougherC/BetterVMAF/pull/8), left unmerged.
No production release tag, production publication, historical release modification,
Apple account purchase/renewal or production feed activation is part of this pass.

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
| Stable Sparkle identity, offline backup, GitHub key settings | Prepared; maintainer participation now | Tested trusted-Mac helper; needs your chosen offline media/passphrase. No production identity created or uploaded; `SPARKLE_PUBLIC_KEY` and `SPARKLE_PRIVATE_KEY` remain absent. This does **not** depend on Apple. |
| Staging identity, signed appcast and archive rejection tests | Complete locally | Disposable identity only; actual pinned Sparkle signing tools plus independent CryptoKit verification. Private key exports excluded from artifacts and removed at exit. |
| Staging install/relaunch | Complete on this Apple Silicon Mac | Installed 1.4.0 → 1.4.1 through Sparkle; About showed 1.4.1 (1004001), second check said current; external fixture scored 33.08 after relaunch. |
| Physical Intel and clean production-Mac acceptance | Still required | Rosetta fixture execution is not native Intel or production Gatekeeper acceptance. |
| Complete FFmpeg corresponding-source delivery and linked-library notices | Open, independent of Apple | Added GPLv3/Netflix license texts and third-party notice. Public upstream build scripts/manifests do not identify every exact input; see the source audit in ENGINE_PROVENANCE.md. Requires separate engine-provenance work or provider input; no provider contacted. |
| `APPLE_TEAM_ID`, Developer ID Application certificate/private key, notarization team API key | Apple account dependent | Obtain after membership renewal, then provision the documented variable and five Apple secrets. |
| Genuine signing, notarization, stapling, Gatekeeper and signed production update | Apple credentials dependent; **unvalidated** | Hardened implementation and preflight prepared. A real successful production preflight and clean-Mac test are mandatory. |
| Production release and feed | Intentionally inactive | A maintainer reviews and publishes a complete immutable draft only after activation checks. |

`python3 scripts/release/readiness.py` re-inspects the live GitHub settings, public
variable formats and environment secret **names**, never secret values. It exits
nonzero for missing settings, inaccessible APIs or the unresolved source-distribution
record. Secret presence is not proof of usable credentials or an offline backup.

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
- Pinned actionlint now checks workflow syntax/expressions in CI, alongside shell/plist
  syntax and the 14 release tests. Package verification checks the newly bundled notices.
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
- Two-version signed staging pair: `build/readiness-staging-verified`. Pinned official
  sign_update verifies the signed feed; independent CryptoKit checks both signatures.
  Real corruption/identity rejection checks pass. The identity is disposable and removed.
- Both packaged engines retain exact SHA-256 and Developer ID signatures. Fixture:
  24 frames, libvmaf 3.2.0; arm64 mean 33.08, x86_64 via Rosetta mean 33.09.
- Separate installed staging pair: `build/readiness-ui/Better VMAF.app` updated through
  Sparkle's real user interface to 1.4.1 and analyzed externally selected fixtures.
- Encrypted-backup helper exercised with a disposable Keychain account. Creation,
  decrypt/compare, actual recovered-key signing, independent verification, changed-byte
  rejection and a separate recovery invocation passed. Test account/backups removed.
- `python3 -B -m unittest discover -s scripts/release -p 'test_*.py'`: 14 passing tests,
  including actual missing-credential package rejection before xcodebuild/output and
  exclusion of credential values from child environments. Existing publication tests
  reject incomplete/mutable assets and wrong metadata; real signature tests reject
  changed bytes. Shell/plist lint, actionlint and `git diff --check` pass.

## Hosted integration evidence

Hosted runs and isolated Pages verification are recorded here after completion. The
first corrected exploratory run proved unsigned packaging executes and uploads its
artifact, then was superseded by the final package run; cancelled exploratory runs are
not counted as successful full-pipeline evidence.

## Remaining activation

Use [PRODUCTION_ACTIVATION.md](PRODUCTION_ACTIVATION.md), which begins with membership
renewal and documents exact provisioning, genuine preflight, artifact acceptance,
draft review/publication and production-feed verification. The separately identified
non-Apple prerequisites remain explicit; this audit does not imply renewal alone is
sufficient. The protected-ref Apple jobs cannot be genuinely exercised from an unmerged
feature branch or without real credentials. No claim of successful Apple signing or
notarization is made.
