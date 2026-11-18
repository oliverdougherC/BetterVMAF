# Bundled engine provenance

Better VMAF ships its FFmpeg/libvmaf engine inside the app bundle. This file records
exactly which binaries are checked in, where they came from, and how they were verified,
so a release can be reproduced and Intel execution is never reintroduced by accident.

## Current engine (2026-11-16)

Two **thin** binaries replace the previous single Intel-only build. The app picks the one
matching the host CPU at launch (see `VMAF/EngineHelper.swift`), so Apple Silicon never
starts a Rosetta process and Intel Macs keep working.

| File | Architecture | FFmpeg | libvmaf | SHA-256 |
| --- | --- | --- | --- | --- |
| `VMAF/Resources/ffmpeg` | arm64 | 9.0.2 | 3.2.0 | `2e11c6f90993cdb79fff84d3f90044d28316b310e75b3e030cfc9a54f2c9d384` |
| `VMAF/Resources/ffmpeg.x86_64` | x86_64 | 9.0.2 | 3.2.0 | `b25689cf2211c0582d317e849912769a1f1c93904fe102c485b5364a425633d1` |

- Source: Martin Riedl's FFmpeg Build Server, `https://ffmpeg.martin-riedl.de/`, macOS
  **release** builds 9.0.2 (`/download/macos/arm64/1789931890_9.0.2/` and
  `/download/macos/amd64/1789931006_9.0.2/`).
- Archive SHA-256 as downloaded: arm64 zip `c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924`,
  amd64 zip `7c6b4125b191cbf773832dc51f424cf2b6bb7da43007d1e066f95909e47cacd4`. Both matched the
  server's published `ffmpeg.zip.sha256`.
- Build configuration (identical for both slices): `--enable-gpl --enable-version3
  --enable-libvmaf --enable-libx264 --enable-libx265 --enable-libaom --enable-libdav1d
  --enable-libwebp --enable-libzimg` (static, `--pkg-config-flags=--static`). `minos 12.0`.
- Code signature: `Developer ID Application: Martin Riedl (KU3N25YGLU)`, hardened runtime,
  timestamped. Xcode's copy phase preserves this signature; the app must not re-sign the
  helpers with a different identity, and notarization must cover both.
- Why not a single universal binary: it is 161 MB, over GitHub's 100 MB per-file limit for
  non-LFS content. Two thin files keep every blob under the limit and make the launch choice
  explicit. Note that every installed .app carries **both** helpers (~161 MB of engine):
  shipping two files removes the Rosetta *dependency*, not the Intel *bytes*. Future per-arch
  release packages (or LFS + a universal helper) could drop the foreign helper from each
  download; until then, `create_dmg.sh` bundles both so one DMG serves both architectures.

## Previous engine (replaced)

`VMAF/Resources/ffmpeg` was **x86_64-only**, `ffmpeg 8.0.1-tessus` from `https://evermeet.cx/ffmpeg/`
(SHA-256 of that file `430d60fbf419dab28daee9b679e7929a31ee9bae53f6e42e8ae26b725584290f`,
`LC_VERSION_MIN_MACOSX 10.12`). evermeet.cx does not publish Apple Silicon builds, so every
analysis ran the Intel helper under Rosetta. macOS flagged the bundle with "includes a component
that will not open in macOS 28", and Intel execution ends at macOS 28.

## Score parity check

The replacement was validated against the old pinned engine on a deterministic fixture
(`testsrc2` 320x180@24, 4 s, encoded CRF 18 reference and CRF 40 comparison), using the exact
`libvmaf=model=path=<vmaf_v0.6.1.json>:log_fmt=json:n_threads=99` graph the app builds:

- Old engine (8.0.1-tessus): mean 67.8460, min 58.9359, max 74.0485.
- New engine (9.0.2): mean 67.8454, min 58.9358, max 74.0483.
- Same 96 frames; maximum per-frame VMAF delta 0.028. Scores are model-for-model equal within
  encoder-thread noise; the app's stored model files are unchanged.

libvmaf 3.2.0 renamed the `integer_motion` feature to `integer_motion2`/`integer_motion3`
(the legacy name cannot be requested from the new engine). The app previously decoded
`integer_motion` strictly, which would have failed every analysis on the new engine.
`VMAFCalculator.FrameMetric` now keeps **both identities as separate optionals**: a 3.x log
fills only `integerMotion2`, a 2.x log only `integerMotion`, and each value re-encodes under
its own key (round-trip never resurrects a feature the engine did not report). The displayed
and exported "Motion" label names its source feature (`integer_motion` or `integer_motion2`),
and results carry the `libvmaf` version from the log for provenance. The two features are
**different measurements**: Motion values from the old and new engines are not directly
comparable and must not be ranked together.

Export shapes follow that identity rule: CSV is an explicitly multi-section document — a
rectangular five-field frame table first (absent motion is an empty field, never a fabricated
`0`), then titled `Aggregate Metrics` (when requested) and an **always-present** `Engine`
section (`Metric`, `Version`, motion feature), so even frame-only exports carry provenance.
`ExportManager.parse(_:)` consumes the entire file and round-trips these sections; the unit
test drives export→parse over the whole document rather than a prefix. JSON omits a motion
key entirely when the engine did not report it; the PDF sizes frame-table columns from the
actual header text so `Motion (integer_motion2)` cannot overlap ADM2, and prints
`Engine: libvmaf <version>` in the summary. `VMAFError` conforms to `LocalizedError` via
`errorDescription` so the UI's `error.localizedDescription` (caught as `Error`) surfaces the
actionable message instead of the generic Cocoa fallback.

The CI job (`Verify bundled FFmpeg engine`) proves the shipped helpers execute by running
`Fixtures/vmaf-reference.mp4`/`vmaf-comparison.mp4` (24 frames, testsrc2 128x72, CRF 20/42;
check the exact command in `.github/workflows/ci.yml`) through the built app's own resources
on both slices and asserting the pinned mean (33.08 ±0.5), the libvmaf 3.2.0 version string,
and the expected feature identities.

## Reproducing the download

```bash
# arm64
curl -L https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip -o ffmpeg-arm64.zip
shasum -a256 ffmpeg-arm64.zip   # expect c8ed4c4e... (verify against the server's .sha256 at download time)
ditto -x -k ffmpeg-arm64.zip out-arm64/ && cp out-arm64/ffmpeg VMAF/Resources/ffmpeg
# amd64
curl -L https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/ffmpeg.zip -o ffmpeg-amd64.zip
shasum -a256 ffmpeg-amd64.zip   # expect 7c6b4125...
ditto -x -k ffmpeg-amd64.zip out-amd64/ && cp out-amd64/ffmpeg VMAF/Resources/ffmpeg.x86_64
chmod 755 VMAF/Resources/ffmpeg VMAF/Resources/ffmpeg.x86_64
```

The server rotates "latest release" build directories; pin the two directory names above rather
than following `/redirect/latest/...` for a reproducible re-download.

## Release-readiness source audit (2026-11-17)

The upstream build manifests remain available for the pinned [arm64 build](https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/versions.txt) and [Intel build](https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/versions.txt).
The flags summarized above are a subset: these helpers also statically link OpenSSL,
libass, fontconfig, freetype, harfbuzz, libbluray, snappy, SRT, libklvanc, zvbi,
OpenH264, OpenJPEG, rav1e, SVT-AV1, vpx, vvenc and audio codec libraries. The prefixes
and clang patch versions differ between architectures. Both upstream manifests name
libvmaf 3.2.0. `ffmpeg -buildconf` records the actual flags without modifying a helper.

The provider ZIPs contain the signed FFmpeg executables. Corresponding sources are
available from the immutable [portable-ffmpeg 9.0.2-1 release](https://github.com/mrkbac/portable-ffmpeg/releases/tag/ffmpeg-9.0.2-1),
which reconstructs the macOS build inputs and identifies both original executables
by their SHA-256 digests. We independently verified both manifests, every published
dependency version against the actual [provider build recipe](https://git.martin-riedl.de/ffmpeg/build-script/commit/6a611e19870e197bc37c6e4c7fccddebd3715466),
86 source and build archives, 18,433 notices, and the locked rav1e dependency bundle.
The script's x264 download targets `master`. VideoLAN's official history at the
Intel build cutoff and the current master tip both identify
`0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee`. Both pinned binaries emit x264 core 165.
The source record is a reconstruction from this evidence. A provider attestation
and byte-identical rebuild remain unavailable.

[Config/EngineSources.json](../Config/EngineSources.json) binds the two pinned
helpers to the source ZIP and the complete notices ZIP. The source ZIP includes
the original archive set, provider recipe, source lock, platform-specific build
records and rebuild instructions. Preflight and tag workflows fetch and verify
the two ZIPs and the tag workflow attaches them to the same release as the DMG.
The draft names and links both downloads. Pages verifies their published digests
before deploying the stable appcast. The read-only audit checks the immutable
origin's published asset digests and the current helpers. Keep these assets
available along with the DMG under GPLv3 §6(d).

The app bundles the FFmpeg GPLv3 text from the upstream `n9.0.2` tag, Netflix's
BSD-2-Clause-Patent license from `v3.2.0`, Sparkle's pinned license and a notice
pointing to the corresponding source and complete third-party notices.
