# BetterVMAF quality assessment research

Research date: 2026-09-13. This is the proposed development strategy, not an implemented capability or benchmark result. Implementation priorities and acceptance criteria live in the [BetterVMAF Linear project](https://linear.app/platinum-labs/project/bettervmaf-bb52721c0728).

## Decision

Make BetterVMAF an evidence-based source-versus-encode inspection app: show several complementary measurements, the moments they identify, and synchronized playback that lets the user judge those moments. Keep a small default UI. Do not invent a weighted “BetterVMAF 94/100” by averaging unrelated metrics. That would obscure disagreement and require a subjective validation program the project has not yet conducted.

The recommended first SDR release is **Standard analysis: VMAF v1 + XPSNR + CAMBI banding diagnostics**, on a shared FFmpeg/libvmaf path. This already adds an independent measurement and inspectable artifact evidence without a new runtime. **Deep analysis adds SSIMULACRA2 only after native conformance, color-conversion and performance gates pass.** It should not block the useful first release or run by default before its Mac cost is known. Preserve old VMAF results with their original model identities. The differentiator is helping someone discover *where and how* the encode differs while understanding what was measured.

Standard/Deep describes which metrics run; Quick/Full describes how much of the video is analyzed. These are separate concepts in the data model. To keep the initial UI small, ship one complete Standard analysis first; introduce sampling and Deep only when the added choice is justified. Both full and sampled SSIMULACRA2 are still framewise image measurements, not a temporal model.

This is a recommendation inferred from the sources below, not evidence that any particular combination has already been shown to outperform all individual metrics on this app's content.

## The June 2026 development that changes the plan

Netflix announced VMAF v1 on June 19, 2026. It incorporates banding and chroma features, enables no-enhancement-gain behavior by default, changes its motion handling, and removes VIF from the core computation. Netflix still identifies film grain, high frame rates and perceptual encoder optimizations as areas for improvement; the announcement describes an HDR version as future work. Thus “VMAF ignores all color and banding” is accurate criticism of the older v0 model, not an accurate blanket statement about current VMAF. [Netflix announcement](https://netflixtechblog.com/vmaf-v1-good-is-not-good-enough-60d7e4244ea8)

The library release is **libvmaf 3.2.0**, while the model family is **VMAF v1.0.16**. These are different version axes. The release describes itself as the initial public v1 release. [libvmaf release notes](https://github.com/Netflix/vmaf/releases/tag/v3.2.0)

An integration caveat remains: the maintainer of ffmpeg-quality-metrics documents a requirement for a libvmaf build newer than 3.2.0 for its FFmpeg v1 route and recommends a source build on macOS. That conflicts superficially with the upstream release headline; do not resolve it by guessing a minimum version. Add an executable compatibility probe using the exact shipped FFmpeg binary, libvmaf binary and model files, and pin the tuple that passes. This research did not run that macOS probe. [ffmpeg-quality-metrics integration documentation](https://github.com/slhck/ffmpeg-quality-metrics#specifying-vmaf-model)

Official model guidance recommends 10-bit processing for SDR, including appropriate conversion of 8-bit inputs. It supplies 1080p 3H, phone 5H and 4K 1.5H/3H models; the 4K 3H model can reach 110. It also documents HFR variants for roughly 50/60 fps and encode-side width, height and bit-depth parameters for CAMBI after upscaling. [Official VMAF v1 model documentation](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md)

Implementation recommendations: model metadata, score range and unit must come from the selected metric definition rather than a universal 0–100 assumption. Preserve original encode geometry/precision alongside comparison geometry. Allow viewing assumptions in advanced settings, with a sensible visible preset rather than silently claiming to predict the actual Mac display.

## Candidate assessment

| Measurement | What it adds | Main boundary | Recommended placement |
|---|---|---|---|
| VMAF v1, exact model pinned | Current trained video quality estimate; compression, chroma and banding sensitivity | Still an imperfect model with viewing assumptions and content blind spots | Primary video estimate, with timeline and model provenance |
| VMAF v0.6.1 NEG | Conservative legacy compatibility for codec comparisons | Older model; NEG is not a guarantee against manipulation | Clearly named fallback and legacy comparison mode |
| SSIMULACRA2 v2.1 | Independent color-aware image quality view, particularly useful for structural damage, smoothing and added edges | Framewise image metric; no native temporal quality prediction | Deep analysis after native parity, color and throughput validation |
| CAMBI, full-reference and per-input values | Localizes banding and distinguishes existing source banding from added banding | Banding-specific; framewise; reference subtraction is not a full causal attribution | Banding diagnostic and heatmaps; reuse VMAF computation where practical |
| XPSNR Y/U/V and upstream aggregate | Cheap relative coding-distortion check; color-plane results expose damage hidden by a luma-only reading | A perceptually weighted error metric, not a complete human-quality model | Standard analysis independent check, with plane-level detail on demand |
| SSIM / MS-SSIM / PSNR | Familiar baselines and reproducibility with other tools | Overlap with structural/error evidence; insufficient to establish robust quality alone | Advanced/export only; do not make each a prominent card |
| Butteraugli, current libjxl version pinned | Spatial difference heatmaps and scrutiny of near-lossless cases | Image metric; not a temporal assessment; version-sensitive | Later on-demand inspection of selected frames |
| ColorVideoVDP | Spatial, temporal and chromatic differences under an explicit display model; HDR path | Display assumptions, heavier runtime, packaging/performance work | Later HDR/temporal investigation with real Mac benchmarks |

SSIMULACRA2 uses a perceptual XYB representation, multiscale structural comparisons and asymmetric error terms for smoothing and added edges. Its documented score range extends below zero, and its published evaluations are image datasets. Its still-image quality labels should not become universal video guarantees. [SSIMULACRA2 author documentation](https://github.com/cloudinary/ssimulacra2/blob/main/README.md)

Its current libjxl implementation transforms both inputs into linear sRGB before calculating the metric. Recommendation: feed high-precision, explicitly color-managed decoded frames, and test the conversion against the reference executable. Avoid an 8-bit screenshot/PNG round trip as the production path. Do not silently apply that SDR interpretation to PQ or HLG content. [Reference implementation](https://github.com/libjxl/libjxl/blob/main/tools/ssimulacra2.cc)

CAMBI full-reference mode is defined as `max(0, distorted_score - reference_score)`. Retain both raw scores as well as this nonnegative difference so source banding and possible debanding remain inspectable. It supports heatmap output. A standalone CAMBI panel is diagnostic evidence even when VMAF v1 already uses CAMBI internally; it should not count as an additional independent vote in an ensemble. [CAMBI documentation](https://github.com/Netflix/vmaf/blob/master/resource/doc/cambi.md)

XPSNR is now in upstream FFmpeg; the original HHI plugin is retained for reference and is unmaintained. Use upstream, not a forked copy of the old plugin. [HHI implementation notice](https://github.com/fraunhoferhhi/xpsnr)

FFmpeg's XPSNR input order is **reference first, distorted second**, unlike the common libvmaf distorted/reference graph. Its `stats_file` emits frame and plane results. Upstream suggests reporting the minimum of the color-plane averages; that value is not the worst-frame score. Input pixel formats must match apart from bit depth. Persist the exact upstream aggregate definition and distinguish it from application percentile statistics. [FFmpeg XPSNR filter documentation](https://ffmpeg.org/ffmpeg-filters.html#xpsnr-1)

The original Butteraugli repository is archived. Its authors describe strongest confidence near barely noticeable differences, and it generates a spatial difference map. Use the maintained libjxl implementation if adding it; treat pooling choice and implementation revision as part of metric identity. [Original author rationale](https://github.com/google/butteraugli), [current libjxl command-line implementation](https://github.com/libjxl/libjxl/blob/main/tools/butteraugli_main.cc)

ColorVideoVDP is an especially relevant later candidate because it explicitly addresses color and time and can compare PQ/HLG video with an appropriate display model. Its documented PyTorch route supports Apple Silicon MPS. This establishes feasibility, not satisfactory speed or battery cost on the user's hardware. [ColorVideoVDP official repository and usage](https://github.com/gfxdisp/ColorVideoVDP)

## What “holistic” should mean in the product

Recommended opening result: source and encode previews; size/bitrate reduction; a short list of moments worth reviewing; compact named metric results. Clicking an identified moment seeks both views to the precise same source/encode frame pair. The timeline and comparison view should receive more attention than a wall of metric abbreviations.

Suggested evidence groups, without inventing calibrated subscores:

- **Quality measurements:** named VMAF and XPSNR results with direction, units and model identity; SSIMULACRA2 added in Deep analysis.
- **Banding:** CAMBI evidence, with source versus encode context and optional heatmap.
- **Consistency over time:** each metric's timeline, lower-tail quality and worst intervals; frame/timestamp integrity warnings.
- **Visual inspection:** synchronized playback, swipe/side-by-side comparison, zoom at 1:1, frame stepping and a clearly labeled absolute-difference view.
- **Efficiency:** bytes saved, bitrate and resolution tradeoffs alongside quality. “50% smaller” is measurable; “95% of original quality” is not justified by a VMAF score of 95.

Use separate metric timelines or a selector rather than plotting dB, SSIMULACRA2 and VMAF on one misleading shared numeric axis. Show disagreement explicitly as “metrics disagree; review these moments.” Without calibration, describe “largest measured differences” or “lowest-scoring moments,” not definitive artifact classifications.

For higher-is-better metrics store mean, median, P5 and minimum; for lower-is-better metrics use P95/maximum as the bad tail. Keep worst single frames separately from worst contiguous windows (for example one-second windows), with duration-aware handling for variable frame rate. Keep native upstream pooling intact; supplemental statistics are separately named. Do not compute harmonic means on arbitrary signed metrics. Worst-score search should merge adjacent frames into a small number of reviewable intervals, deduplicate between metrics and record why each interval was selected.

Adaptive sampling can improve responsiveness, but must not hide its coverage. A Quick scan should report exact analyzed frames/time and be visibly distinguished from a Full analysis. Do not present sampled P5 values as the population percentile or display a statistical confidence interval without a valid sampling method. A periodic fixed stride can miss periodic artifacts; prefer stratified scene coverage or seeded sampling plus expanded analysis around suspect intervals. SSIMULACRA2 frames can be sampled independently; metrics with temporal context must preserve the needed neighboring frames and frame-rate semantics.

## Foundational correctness comes before more metrics

These are proposed engineering acceptance rules:

1. **Verify correspondence.** Compare the same content and timestamps. Detect duration, edit, crop, frame-rate and frame-count mismatches. A known constant offset can be corrected transparently; a dropped frame must not cause all later comparisons to shift. Never silently use frame index when PTS correspondence disagrees.
2. **Do not silently normalize away defects.** Contrast, sharpness, denoising, crop or color changes can be exactly what the user wants to detect. Normalization should reconcile representation, not change appearance. Persist every transform.
3. **Separate legitimate scaling comparison from mismatched content.** If the encode is smaller, upscale it to the declared viewing/reference canvas using a recorded kernel. Do not downscale the reference by default, which can conceal lost detail. Preserve sample aspect ratio, display crop, rotation and chroma siting.
4. **Preserve color intent.** Track matrix coefficients, primaries, transfer function, full/limited range, chroma siting and bit depth. Unknown metadata needs a documented assumption or an actionable prompt. A uniform forced BT.709 conversion can itself create the apparent error.
5. **Handle HDR as an explicit capability.** SDR metrics on tone-mapped HDR characterize that specific tone-mapped rendering, not native HDR quality. Keep HDR unsupported for normative scoring until a tested pipeline exists; optionally allow a clearly labeled SDR preview. CAMBI's ability to process particular HDR transfer behavior alone does not validate all of VMAF for HDR.
6. **Keep time intact.** Do not use frame duplication/interpolation to make counts match without exposing it. A temporal metric or metric motion feature is not a substitute for detecting dropped, duplicated, reordered or frozen frames. Distinguish an actual repeated shot from a decode/encode timing defect.
7. **Make results reproducible.** Include source/encode hashes, selected stream IDs, original timestamps, compared timestamp mapping, decode path, comparison transforms, metric versions/model hashes, frames analyzed, pooling definitions, app version and analysis mode in exportable JSON.
8. **Represent exceptional values.** Lossless comparisons can generate infinite PSNR/XPSNR, while some metrics can be negative. Store those values safely in a typed schema (not illegal JSON numeric infinity) without coercing them to zero, failure, or 100.

## Response to “VMAF can be gamed”

The criticism has experimental support for older VMAF and NEG versions: a 2021 paper demonstrated preprocessing that increased objective scores without a corresponding subjective benefit. Those findings should not be misrepresented as measurements of the June 2026 v1 model. They establish the need to test adversarial content and avoid “ungameable” claims. [Siniukov et al., Hacking VMAF and VMAF NEG](https://arxiv.org/abs/2107.04510)

NEG specifically addresses enhancement gain in codec comparisons; legacy model files ending in `neg` select that behavior. Recommendation: use NEG when falling back to old VMAF for source fidelity and label it clearly. Do not claim that NEG proves creative-intent preservation or solves every preprocessing attack. [Netflix legacy-model guidance](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v0.md)

A metric ensemble is also a target for optimization. Adding five correlated metrics and averaging them can still reward unwanted changes and hides the reason for a result. Until BetterVMAF has representative subjective labels, the more defensible design is separate metric evidence plus targeted human review. If a learned composite is ever pursued, specify intended viewing conditions/content, split data by source scene, keep a locked unseen holdout, compare against individual baselines, report uncertainty, and publish failure cases.

## Validation corpus and methodology

Start with a manageable public-source suite: 12–20 short source scenes with explicit redistribution rights, spanning live action, anime/animation, film grain, skin, foliage/water, dark gradients, screen/text, static scenes, high motion and multiple frame rates. Keep the engineering fixtures small and synthetic where possible. Large media can live in a checksummed downloaded corpus, outside ordinary Git history.

Generate a frozen distortion matrix. The point is not to assume that one metric must win on every sample; it is to expose pipeline errors and characterize blind spots.

| Fixture family | Examples | Required evidence |
|---|---|---|
| Identity | Same stream; lossless rewrap; lossless decode/re-encode | Correct correspondence, deterministic metric output, exception-value handling |
| Compression ladders | Several quantizer/bitrate settings for AVC/HEVC/AV1 | Reasonable trends and recorded exceptions; no demand for strict monotonicity on every frame |
| Enhancement attacks | Sharpening sweep, contrast/gamma shifts, denoise, oversharpen + recompress | Legacy/v1/independent metrics compared; inspect ranking reversals rather than asserting immunity |
| Color-only damage | Chroma blur, desaturation, hue shift, U/V corruption with luma held constant | Independent color-aware evidence reacts; luma-only blind spots documented |
| Banding | Smooth ramps, dark skies, 10-to-8-bit quantization with/without dither | CAMBI source/encode/delta checked; no mistaken punishment of identical source banding |
| Time defects | One dropped frame, repeat, freeze, shifted start, variable-rate timestamps | Validity layer identifies correspondence problem and navigates to defect |
| Resizing/crop | Downscale/upscale, odd aspect ratio, rotated stream, shifted crop | Policy applied visibly, no false perfect score from concealed downscaling |
| Realistic weak cases | Film grain synthesis, heavy texture, anime line art, high motion | Known limitations surfaced, playback evidence retained |
| HDR boundary | PQ, HLG, missing metadata, SDR/HDR mismatch | Unsupported/native/preview paths labeled correctly; no silent SDR quality claim |

For a small human review, randomize blinded source/encode or A/B presentation; use original motion playback and matched viewing conditions, not only freeze frames. Record preference, observed artifact and uncertainty. Keep calibration/training scenes separate from evaluation scenes. Initially this is a sanity check of product usefulness and metric disagreements, not proof of universal perceptual validity. A user preference for denoising can differ from source fidelity; let those questions remain distinct.

Conformance tests should compare each adapter against a pinned upstream executable on known decoded inputs. Independently check stream orientation with an asymmetric test, especially XPSNR versus libvmaf. Cross-platform comparisons should use explicit justified tolerances because optimized floating-point paths may differ slightly. Freeze per-metric expected ranges only after measuring authoritative outputs; do not fabricate expected scores.

## Native Mac integration and performance

Recommended first architecture: SwiftUI for presentation; an isolated background analysis service; narrow adapters for FFmpeg/libvmaf and a compiled C/C++ SSIMULACRA2 helper. Prefer supported upstream computation before rewriting a perceptual metric in Swift or Metal. A single shared decode/normalization pipeline should feed multiple metrics when practical, with bounded frame buffers and backpressure. If the existing architecture uses processes, a coherent FFmpeg filtergraph plus a separately benchmarked SSIMULACRA2 path is a reasonable transitional design.

The metric CPU path and video decode path are separate choices. A hardware decoder does not imply the metric runs on the GPU. Validate hardware/software decoding equivalence on the supported codecs before changing the default. Do not promise that enabling VideoToolbox or “using Metal” is automatically faster once transfers, conversions and memory pressure are included.

libvmaf has architecture-specific CPU instruction support, including an ARM64 NEON control in its public API. Highway, used by libjxl, supports ARM SIMD. These are reasons to benchmark native CPU builds first, not evidence of any particular throughput on M-series Macs. [libvmaf configuration API](https://github.com/Netflix/vmaf/blob/master/libvmaf/include/libvmaf/libvmaf.h), [Highway official project](https://github.com/google/highway)

Benchmark at least one base Apple Silicon laptop and the user's Mac if available: 1080p and 4K, 8/10-bit, 24/60 fps, hardware and software decode, full stack and each component separately. Capture first-result latency, fps, peak RSS, cancellation latency, CPU/GPU occupancy and energy/power observations. UI smoothness has its own acceptance evidence: frame pacing while scrolling, seeking and cancelling under analysis load. Avoid per-frame main-actor publication, eager all-frame thumbnails and unbounded heatmap storage; cache compact metric records and generate full-resolution frame views on demand.

For later ColorVideoVDP work, package size, Python/PyTorch deployment and sustained MPS memory use are explicit spike outputs. A Metal port is optional future optimization and would need parity fixtures. CUDA/HIP implementations do not solve Apple GPU integration.

## Licensing and distribution facts to record

- libvmaf: BSD-2-Clause-Patent. Retain its notices and exact vendored identity. [License](https://github.com/Netflix/vmaf/blob/master/LICENSE)
- libjxl: BSD-style permissive license with redistribution conditions. Its transitive dependencies need their own notices; do not infer the whole package's terms from one file. [License](https://github.com/libjxl/libjxl/blob/main/LICENSE)
- ColorVideoVDP: MIT. [License](https://github.com/gfxdisp/ColorVideoVDP/blob/main/LICENSE)
- FFmpeg: LGPL by default, with GPL applying when configured with relevant GPL components. Pin the build configuration and distribute required notices/source material; this cannot be settled solely by saying the app is free. [FFmpeg licensing documentation](https://ffmpeg.org/legal.html)

No paid metric SDK is necessary for the proposed stack. Exact distribution compliance depends on the actual bundled binaries and configuration, which this subtask did not inspect.

## Suggested deliverable-sized backlog

1. **Comparison contract and validity gate:** timestamps, color, geometry, dynamic range and transform provenance. Acceptance: identity, offset, drop, color-range and HDR fixtures behave as specified.
2. **Versioned analysis result schema and metric adapters:** typed units/ranges/directions, partial results, model hashes and nonfinite values. Acceptance: imports of legacy results remain honest and deterministic export round-trips.
3. **VMAF v1 macOS compatibility spike:** exact FFmpeg/libvmaf/model tuple, 10-bit SDR path and CAMBI encode-side metadata. Acceptance: real arm64 smoke test and independent upstream score parity; a named legacy NEG fallback if the capability is absent.
4. **XPSNR and banding diagnostic integration:** correct asymmetric input order, native aggregates, per-plane/frame output, source/encode CAMBI context. Acceptance: orientation and color-only fixtures plus banding baseline.
5. **SSIMULACRA2 native backend:** high-precision managed color conversion, pinned upstream implementation and benchmarks. Acceptance: reference parity; negative values; cancellation/memory limits; no silent HDR application.
6. **Linked timeline and worst-moment navigation:** mean/tails/intervals and exact paired-frame seeking. Acceptance: injected localized damage appears and click lands at the actual corresponding frame.
7. **Synchronized visual comparison:** 1:1, zoom/swipe/frame step, difference/heatmap labeling. Acceptance: matching color and timing in both panes and responsive playback under compute load.
8. **Frozen corpus and adversarial regression suite:** licensed/checksummed sources, synthetic distortions, known blind spots and small blinded review. Acceptance: reproducible generation + documented metric disagreements.
9. **Apple Silicon performance budget:** capture baseline and instrument hot paths before optimizing. Acceptance: measured throughput/memory/energy and UI/cancellation evidence, rather than unmeasured performance claims.
10. **HDR/temporal research spike:** ColorVideoVDP MPS deployment and explicit display assumptions, reassess latest HDR VMAF availability at implementation time. Acceptance: feasibility/cost/accuracy report and a supported-versus-unsupported matrix; separate later feature decision.
