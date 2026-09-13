# BetterVMAF

A free native macOS app for comparing an encoded video against its source.

BetterVMAF currently calculates **VMAF v0.6.1** with bundled FFmpeg and displays summary statistics and per-frame charts. The next development phase expands that into a complementary quality profile, synchronized visual inspection, and clearer evidence of what an encode changed.

## Available today

- SwiftUI interface for one comparison or a queue of encodes against one reference.
- VMAF mean, minimum, maximum, harmonic mean, and frame-level graphs.
- Bundled legacy 1080p and 4K VMAF models with automatic selection.
- CSV, JSON, and PDF export.
- Progress and diagnostic output from FFmpeg.

The current “heat map” is a colored score chart over time, not a spatial map of pixel damage. Multi-metric analysis and synchronized source/encode playback are planned capabilities.

## Install

Download a DMG from [GitHub Releases](https://github.com/oliverdougherC/BetterVMAF/releases) and drag **Better VMAF** into Applications. Existing releases are not Developer ID signed; macOS may require opening the app through **System Settings → Privacy & Security**.

The current source project targets **macOS 15.2 or later**. Older release assets may differ. The checked-in FFmpeg executable is **Intel x86_64**, so its execution on Apple Silicon currently requires Rosetta. A native Apple Silicon engine is a high-priority roadmap item.

## Understand the result

VMAF predicts perceived quality relative to a reference under a model's assumptions. **A score is not a percentage of retained quality, and 100 is not proof of identical pixels or invisible degradation.** Scores depend on the model, viewing assumptions, input correspondence, and preprocessing. Inspect the video when making an encoding decision.

Current limitations include a 30 fps assumption in displayed timestamps, incomplete alignment/color validation, and a batch cancellation race. See the [source audit](docs/REPOSITORY_AUDIT.md) for evidence and the development backlog for planned repairs.

## Develop

```bash
git clone https://github.com/oliverdougherC/BetterVMAF.git
cd BetterVMAF
open VMAF.xcodeproj
```

Use the shared **VMAF** scheme. See [CONTRIBUTING.md](CONTRIBUTING.md) for build/test commands, workflow, and packaging. `./create_dmg.sh` creates `Better-VMAF.dmg`.

## Development direction

The [BetterVMAF Linear project](https://linear.app/platinum-labs/project/bettervmaf-bb52721c0728) contains the implementation backlog, priorities, dependencies, and acceptance criteria.

- [Metric strategy and validation](docs/QUALITY_STRATEGY.md): current research and the proposed quality profile.
- [Product direction](docs/PRODUCT_DIRECTION.md): existing alternatives and the intended comparison workflow.
- [Repository audit](docs/REPOSITORY_AUDIT.md): verified code findings and development risks.
- [Branch archive](docs/BRANCH_ARCHIVE.md): preserved legacy branch tips and restoration instructions.
- [Agent guidance](AGENTS.md): project-specific engineering and UX rules.

## License and dependencies

BetterVMAF's own source is [MIT licensed](LICENSE). Bundled third-party components retain their own licenses. The existing FFmpeg binary identifies GPL and version-3 build options; the app's MIT license does not replace those terms. Reproducible helper builds, notices, and corresponding-source provenance are tracked before the next release.

Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/), [FFmpeg](https://ffmpeg.org/), and [Netflix libvmaf](https://github.com/Netflix/vmaf).
