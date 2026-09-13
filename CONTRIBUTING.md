# Contributing

Start from current `main`, read [AGENTS.md](AGENTS.md), and link changes to the existing Linear requirements. Keep unrelated work and archive/release refs intact. The 2.0 integration is reviewed as one PR; do not merge or publish a release without the maintainer's approval.

## Native build and test

Use Apple Silicon, macOS15.2+ and compatible Xcode16+. The project uses Swift5 language mode. The bundled analysis engine is arm64 only; building a universal app does not provide Intel analysis support.

```bash
xcodebuild -project VMAF.xcodeproj -scheme VMAF -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project VMAF.xcodeproj -scheme VMAF -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -resultBundlePath build/TestResults.xcresult -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test
```

Use a fresh result-bundle path on repeat runs. Tests exercise parsing, exceptional metric values, timestamp mapping, process kill/reap, stable run identities, export provenance and native engine identity. Actual player frame output and interactive video inspection are distinct from compilation or launch; record both where a playback behavior changes. [Validation](docs/VALIDATION.md) states what was run.

The engine folder is an explicit Xcode folder resource. Do not flatten its files or add a system-engine fallback. `scripts/engine/build.py` rebuilds exact pinned sources; [ENGINE.md](docs/ENGINE.md) documents prerequisites and conformance. Do not preserve inherited environment dumps in logs or evidence; build tools use a restricted environment.

## Corpus, conformance and performance

[CORPUS.md](docs/CORPUS.md) provides generation commands, source rights and hashes. Keep media and full metric outputs outside Git; commit small manifests, scripts and concise evidence. Compare against the pinned upstream executable with the same preprocessing. Record measured exceptions, including identity/model behavior, rather than inventing ideal expected scores or changing tolerances to hide failures.

[PERFORMANCE.md](docs/PERFORMANCE.md) separates headless throughput, synthetic chart preparation and actual app measurements. Avoid unsupported claims about battery use, human visibility or GPU acceleration. No unrelated metric scales may be averaged into a universal score.

## Local review package

```bash
./create_dmg.sh
# Or reuse an already validated Release app:
./create_dmg.sh --app '/absolute/path/Better VMAF.app' --output /tmp/Better-VMAF-review.dmg
```

The packaging script verifies arm64 helpers, hashes/models, system-only dynamic dependencies and executable permissions, signs helpers before the app, includes corresponding sources/notices, creates the DMG, then mounts it read-only and repeats native metric checks. Sidecars record version, source commit and checksums. No paid account is required. This does not perform public notarization or establish every supported OS/hardware combination.

## Completion evidence

Add a regression for a repaired defect. Build, run the relevant native suite, inspect UI behavior, and validate the final combined commit. Use Linear statuses honestly: unmerged validated implementation awaits review; missing acceptance remains in progress. See [VALIDATION.md](docs/VALIDATION.md) for the issue mapping and precise gaps. Commit messages record intent and useful Git-native `Tested:`, `Constraint:`, `Rejected:` and `Not-tested:` trailers.
