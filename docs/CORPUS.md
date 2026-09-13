# Reproducible comparison corpus (PLA-531)

The frozen corpus contains **16 short source scenes and 57 generated artifacts**: eight procedural scenes and eight licensed excerpts. There are 41 valid same-geometry/cadence Standard comparisons, plus deliberately invalid correspondence, geometry, metadata and HDR cases. Media lives outside Git; commands, rights, hashes, decoded timestamps and observed outputs are committed. This is an engineering corpus, not a calibrated human-opinion dataset.

## Acquire and reproduce

The generation environment needs FFmpeg with FFV1, libx264, libx265, libsvtav1, zscale and drawtext. These are **fixture-generation dependencies**, not app runtime dependencies. The exact measured executable and installed versions are in [generation environment](evidence/corpus-generation-environment.json). Different encoder builds may produce different container/bitstream hashes; verify the new manifest instead of claiming byte identity across versions.

```bash
python3 scripts/validation/fetch_corpus.py --root ../BetterVMAF-corpus
python3 scripts/validation/generate_corpus.py --root ../BetterVMAF-corpus
python3 scripts/validation/measure_corpus.py --root ../BetterVMAF-corpus --engine VMAF/Resources/engine
```

`--synthetic-only` omits both downloads. The fetcher rejects changed archive checksums. Generation runs each recorded argument array without a shell, stores per-artifact SHA-256/probe/command data in `generated/manifest.json`, and verifies decoded lossless identity. Its final `setparams` is intentional: output color flags alone were overwritten by decoded frame metadata in the tested FFV1 and H.264 paths. Explicit `chroma_sample_location=left` is retained. Public excerpts have a recorded BT.709 SDR and square-pixel assumption; they are not camera originals. Rotation uses an input `display_rotation` override followed by stream copy, producing a verified MOV display matrix.

The measured run is at `/Users/ofhd/Developer/BetterVMAF-corpus`. It is about 101 MB of generated media; downloaded archives, extracted movies, optional experiment environments and raw metric logs are separate. Do not add those directories to ordinary Git history.

## Rights and scene coverage

[Source archive manifest](../tests/fixtures/corpus-sources.json) pins URLs, license pages and hashes. [Full corpus manifest](evidence/corpus-manifest.json) pins extracted source hashes, all extraction/distortion commands and timestamps.

| Source | Rights and attribution | Excerpts / coverage |
|---|---|---|
| Procedural FFmpeg scenes | Repository MIT; BetterVMAF contributors; no third-party media | 24, 60 and 24000/1001 fps motion, bright/dark 10-bit ramps, seeded grain, static line art, screen text |
| Big Buck Bunny | CC BY 3.0; © 2008 Blender Foundation / www.bigbuckbunny.org; [author license](https://peach.blender.org/about/) | 35, 60, 180 and 250 seconds, two seconds each: foliage/fur, character, group action, branch/depth |
| Tears of Steel teaser | CC BY 3.0; (CC) Blender Foundation / mango.blender.org; [author license](https://mango.blender.org/sharing/) | 0, 2, 16 and 22 seconds, two seconds each: live-action skin/foliage, dark rigging and detailed objects |

Audio is removed. The separately licensed Tears of Steel soundtrack is not used. Excerpts are resized to 640 pixels wide with preserved encoded aspect, explicitly assumed square pixels, and FFV1 10-bit BT.709 limited output. Synthetic grain and line art cover engineering stress patterns; they do not represent the full distribution of real film grain or anime. Fourth excerpts of each public movie are marked held out; no composite, trained threshold or calibration was fitted to any scene.

## Adversity matrix

| Family | Generated IDs | Expected use |
|---|---|---|
| Identity/lossless | Source compared to itself; `identity` decoded FFV1 re-encode | Exact decoded identity; infinite XPSNR is legitimate |
| Compression | `avc_q18/q30/q42`, `hevc_q18/q30/q42`, `av1_q18/q30/q42` | Record codec-specific ladders; quantizers are not equivalent between codecs |
| Enhancement | `sharpen`, `oversharpen`, `contrast`, `gamma`, `denoise`, `sharpen_recompress` | Characterize changes and disagreements; no immunity claim |
| Color-only | `chroma_blur`, `desaturate`, `hue`, `uv_corrupt` | All decoded Y samples verified identical and chroma verified different |
| Banding | `gradient`, `dark_gradient`, `band_8bit`, `band_dither` | Source/encode/full-reference CAMBI; source banding is not new banding |
| Time | `shift_one`, `drop_one`, `repeat_one`, `freeze`, `short_encode` in both directions, `vfr`, `24_to_30` | Refuse unexplained correspondence/cadence; no hidden held-last-frame scores |
| Geometry | `resize`, `crop_shift`, `non_square`, `rotated`, `interlaced` | Explicit supported viewing policy or actionable refusal |
| Range/metadata/HDR | `full_range`, `missing_metadata`, `pq_boundary`, `hlg_boundary` | Explicit range conversion; unknown metadata/HDR boundaries |
| Localized damage | `damage_brief`, `damage_periodic`, `damage_sustained` | Black frame 13; frames 5/17/29/41; frames 24–35, respectively, at 24 fps |
| Runtime faults | Core regression tests and process fixtures | Malformed output, missing primary/capability, launch failure, cancellation, rerun/input identity changes |

PQ/HLG **boundary** files deliberately relabel SDR sample codes to exercise metadata refusal. They are not photometric HDR scenes. [The separate HDR experiment](EXPERIMENTS.md) constructs actual PQ/HLG encoded float samples under an explicit display model.

## Measured results and exceptions

[Corpus metric evidence](evidence/corpus-metrics.json) retains exact engine/model hashes, commands, native pooling, evaluated frame numbers, timing and peak RSS for all 41 successful standalone runs. These use the shipped native helper; libvmaf takes distorted/reference while XPSNR takes reference/distorted. Both consume the same 10-bit frame path and explicit `shortest=1:repeatlast=0`. Original encode precision/dimensions are supplied to model CAMBI and its diagnostic instance. The [actual-service 58-case matrix](evidence/analysis-service-corpus.json) records 42 accepted and 16 refused policies; scoring invalid alignments is not a conformance success.

[Engine evidence](ENGINE.md) compares FFmpeg against the pinned standalone upstream executable on exact decoded10-bit inputs, with a 1e-6 absolute tolerance. That tolerance reflects the same implementation/architecture and JSON precision; it is not a claim about perceptual uncertainty. [Decoded corpus checks](evidence/corpus-checks.json) prove luma preservation for color-only fixtures and link measurements to current source hashes.

Observed exceptions are retained:

- Identical `dark_gradient` yields VMAF **94.909757**, XPSNR **+∞** on all planes, CAMBI source/encode **8.215243**, and full-reference CAMBI **0**. The model's internal CAMBI uses distinct parameters. Source banding and model behavior do not justify changing an identity score to100.
- Constant replacement of chroma in `desaturate` and `uv_corrupt` yields VMAF **100**, although all chroma samples differ and the independently measured minimum-plane XPSNR is **−3.0386 dB** and **−5.3296 dB**. This is a concrete blind spot on this synthetic scene; do not imply that v1 is insensitive to every color error. Hue rotation and chroma blur do reduce VMAF.
- `band_dither` has lower standalone CAMBI than `band_8bit`, but also lower VMAF. Neither has positive full-reference CAMBI against this already-banded source. Dither preference cannot be reduced to a forced common ranking.
- Brief/periodic/sustained black damage yields means near97.9/91.7/75 while individual damaged frames reach the model floor. The global mean alone hides brief damage.

## Visual selection and review

`visual_review.py` creates a seed 531, shuffled, blinded four-pair still audit. [Recorded observations and key](evidence/corpus-visual-review.json) identified no visible change in identity, oversharpened outlines, severe color replacement, and a subtle brightness change. All eight final public excerpts were visually checked; initial teaser title-card excerpts were replaced with actual scene content. This Codex still inspection validates fixture selection/corruption; it is **not human subjective calibration or temporal viewing evidence**.

The native application fixed-task study and its motion/playback limits are in [alternative comparison](ALTERNATIVE_COMPARISON.md). Current AVC review files and hashes are in [review pair provenance](evidence/corpus-review-pair.json): `review_reference.mp4` / `review_sustained.mp4`, 640×360 at 24 fps, black damage in **[1.0,1.5) seconds**, frames 24–35. Both have the same documented10→8-bit conversion and H.264 CRF0 encoding. They were regenerated to repair metadata after the first comparison study; that study retains its original historical hashes.

Remaining methodological limits: two-second clips, modest natural-source resolution, compressed public source movies, no genuine HDR camera corpus, and no human blinded moving-video panel. These limits prevent a universal quality claim; they do not negate the deterministic pipeline failures and metric disagreements this corpus exposes.
