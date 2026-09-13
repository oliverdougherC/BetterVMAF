# BetterVMAF

A free, local, native macOS app for comparing an encode with its source: see the space saved, inspect named quality measurements, and jump to the video intervals they identify.

The **2.0 review branch** adds Standard SDR analysis with **VMAF v1.0.16, XPSNR, and source-aware CAMBI**, using a pinned native Apple Silicon engine. This is an unmerged review build; existing GitHub releases describe earlier versions.

## Compare and inspect

1. Choose or drop the original source and encode. Viewing assumptions are available before analysis.
2. Analyze the full matched video. Cancellation stops and reaps the owned engine process.
3. Select a moment to seek both videos to its frame pair. Use side-by-side or wipe, shared zoom/pan, 1:1 inspection, frame stepping and interval looping.
4. Export a short PDF, per-frame CSV, or a versioned JSON record with identities, original timestamps, model hashes and preprocessing.

VMAF is a model estimate, **not a percentage of retained quality or proof of transparency**. XPSNR retains its own dB scale and native plane aggregation. CAMBI includes source banding and its full-reference difference; VMAF v1 already uses CAMBI internally, so the diagnostic is not another independent vote. Review intervals use supplementary duration-weighted tails, preserve disagreements, and lead to exact video evidence. File-size and container-bitrate savings are separate measurements.

Batch mode compares a source against up to eight encodes, with stable job identities, cancellation and retry. Profiles and coverage must agree before results are compared. Resources are bounded; the current queue retains at most one million measured frame samples, and each analysis accepts at most 500,000 decoded frames. Larger work must be divided into documented matching intervals. The queue is an in-session workflow, not persistent scheduling.

## Supported comparison boundary

- Apple Silicon; project minimum macOS **15.2**. Native host evidence and CI versions are recorded in [validation](docs/VALIDATION.md).
- Explicitly tagged **BT.709 SDR**, full or limited range, 8/10-bit 4:2:0, left/center chroma location, progressive square pixels and one unambiguous video stream.
- Equal coded dimensions, zero rotation, matched decoded presentation timestamps and frame durations. Container timestamp quantization is checked within a bounded one-to-one correspondence policy. A conservative content screen refuses strong nearby displacement evidence; it cannot prove semantic identity for all scenes.
- Original precision, dimensions, metadata and transforms remain in every result. Missing metadata, unexplained edits/cadence changes, HDR, interlace and unsupported geometry produce actionable refusals.
- Playback uses AVFoundation and its display color management. Some FFmpeg-readable formats, including FFV1/Matroska combinations, cannot play natively. The result remains available with an explicit viewer error; no substitute video is silently shown.

Scaling/rotation normalization, native HDR quality, SSIMULACRA2 Deep mode and Quick sampling are **not enabled**. See [experiments](docs/EXPERIMENTS.md) for measured decisions and remaining gates. Intel helpers are not included in this review package; existing release history and archive tags are preserved.

## Build and review locally

```bash
xcodebuild -project VMAF.xcodeproj -scheme VMAF -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
./create_dmg.sh
```

No Homebrew or Rosetta runtime is required for the bundled engine, and no paid Apple developer account is needed for local development. Packages use ad-hoc signing, not Developer ID signing/notarization. The DMG includes dependency notices, a verified corresponding-source archive, and checksum/provenance sidecars. Read [CONTRIBUTING.md](CONTRIBUTING.md) for native tests and packaging commands.

## Evidence and development

- [Validation and issue mapping](docs/VALIDATION.md)
- [Architecture and comparison contract](docs/ARCHITECTURE.md)
- [Engine source/build/model provenance](docs/ENGINE.md)
- [Reproducible corpus](docs/CORPUS.md)
- [Measured Mac performance](docs/PERFORMANCE.md)
- [Product workflow](docs/WORKFLOW.md) and [alternative comparison](docs/ALTERNATIVE_COMPARISON.md)
- [Quality strategy](docs/QUALITY_STRATEGY.md), [historical source audit](docs/REPOSITORY_AUDIT.md), [archived branches](docs/BRANCH_ARCHIVE.md)
- [Existing Linear project](https://linear.app/platinum-labs/project/bettervmaf-bb52721c0728)

## License

BetterVMAF source is [MIT licensed](LICENSE). Bundled FFmpeg, libvmaf, dav1d, libsvm and model resources retain their own licenses and notices; the app's license does not replace them. Exact components, license texts, source revisions and build configuration are in [engine provenance](docs/ENGINE.md) and the package.
