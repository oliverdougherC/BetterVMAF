# BetterVMAF

A free, native macOS app for comparing an encoded video against its source.

BetterVMAF currently calculates **VMAF v0.6.1** with bundled FFmpeg and displays summary statistics and per-frame charts. The next development phase expands that into a complementary quality profile, synchronized visual inspection, and clearer evidence of what an encode changed.

## Available today

- SwiftUI interface for one comparison or a queue of encodes against one reference.
- VMAF mean, minimum, maximum, harmonic mean, and a per-frame quality heat map.
- Bundled legacy 1080p and 4K VMAF models with automatic selection.
- CSV, JSON, and PDF export.
- Progress and diagnostic output from FFmpeg.

The heat map plots per-frame VMAF score over time: colour is the score, and shading density or a min–max envelope carries the frames as the clip grows longer. It is a temporal quality view, not a spatial map of pixel damage. Multi-metric analysis and synchronized source/encode playback are planned capabilities.

## Install

Download the latest signed DMG and drag **Better VMAF** into Applications.
Starting with 1.4.1, use **Better VMAF → Check for Updates…** or opt into
automatic updates. If you’re upgrading from an earlier version, install the
signed DMG once to start receiving Sparkle updates. [Latest GitHub release](https://github.com/oliverdougherC/BetterVMAF/releases/latest)

The current source project targets **macOS 15.2 or later**. Older release assets may differ. The bundled FFmpeg engine ships separate native **arm64** and **x86_64** binaries and launches the one matching your Mac, so analysis runs natively on Apple Silicon without Rosetta and continues to run on Intel Macs. See [engine provenance](docs/ENGINE_PROVENANCE.md) for the pinned builds and checksums.

## Understand the result

VMAF predicts perceived quality relative to a reference under a model's assumptions. **A score is not a percentage of retained quality, and 100 is not proof of identical pixels or invisible degradation.** Scores depend on the model, viewing assumptions, input correspondence, and preprocessing. Inspect the video when making an encoding decision.

Current limitations include a 30 fps assumption in displayed timestamps and incomplete alignment/color validation. See the [source audit](docs/REPOSITORY_AUDIT.md) for evidence and the development backlog for planned repairs.

## Develop

```bash
git clone https://github.com/oliverdougherC/BetterVMAF.git
cd BetterVMAF
open VMAF.xcodeproj
```

Use the shared **VMAF** scheme. See the [contributing guide](CONTRIBUTING.md)
for build and test commands and the [documentation index](docs/README.md)
for release, engine and product references.

## License and dependencies

BetterVMAF's source is [MIT licensed](LICENSE). The bundled FFmpeg helpers are licensed under GPL version 3 or later. See [engine provenance](docs/ENGINE_PROVENANCE.md) for the pinned corresponding source and third-party notices.

Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/), [FFmpeg](https://ffmpeg.org/), and [Netflix libvmaf](https://github.com/Netflix/vmaf).
