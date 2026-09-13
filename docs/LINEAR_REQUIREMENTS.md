# Live Linear requirements

## PLA-519: Establish clean main, archive legacy branches, and verify macOS CI

Status: Done

Starting main: 209921cd525e4331b361bf78c428787fe3e6f946. Cleanup commit: [https://github.com/oliverdougherC/BetterVMAF/commit/78f6631605132d0ea75cf92869e65231968d46fb](<https://github.com/oliverdougherC/BetterVMAF/commit/78f6631605132d0ea75cf92869e65231968d46fb>).

Includes shared Xcode scheme, module/test-host repairs, removal of tracked user state, portable local packaging, CI, contributor/agent guidance, and sourced strategy/audit documents. nano and test preserve distinct history, but source is identical between them and obsolete relative to main.

Acceptance:

* Guarded archive workflow verifies both recorded tips, creates/verifies archive tags, then removes nano/test with expected-tip leases.
* Live GitHub lists main as the only branch; release tags and both archive refs remain intact.
* macOS Release build and current unit/UI suite pass; failures are repaired without weakening checks.
* Local checkout matches main and is clean.
* Linear contains the full research, audit, milestones, dependencies, and remaining work.

Current tests are templates/launch checks, so green CI is build readiness, not metric validation.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

## Completion evidence — 2026-09-13

* Main is `78f6631605132d0ea75cf92869e65231968d46fb`; local working tree is clean.
* [macOS CI](<https://github.com/oliverdougherC/BetterVMAF/actions/runs/34730360400>) passed syntax/project validation, Release build, and current unit/UI tests.
* [Archive workflow](<https://github.com/oliverdougherC/BetterVMAF/actions/runs/34730360396>) succeeded. Live API verification shows only main; archive/nano-2026-09-13 and archive/test-2026-09-13 point to their exact reviewed commits. Existing 1.0–1.3 tags remain.
* Five milestones, 26 issues, and complete quality/product/audit documents are present. Dependencies and acceptance criteria have been populated.
* These are development-foundation results. The planned app correctness, native-engine, multi-metric, visual comparison, and packaged-release work is not claimed implemented.

Dependencies: {"blocks":[{"id":"PLA-528","title":"Ship a reproducible native Apple Silicon analysis engine"},{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"}],"blockedBy":[],"relatedTo":[],"duplicateOf":null}

## PLA-520: Replace template-only coverage with analysis regression seams

Status: Todo

The current unit test contains no assertions; UI tests only launch and measure launch. Introduce narrow injectable process/metadata/result boundaries and a small deterministic fixture harness without rewriting the app.

Acceptance:

* Tests can exercise job lifecycle, parser failures, provenance changes, and timestamp mapping without launching real movie-length work.
* Include a real short process integration path and a bundled-engine smoke when capability permits.
* Each repaired bug gains an observable regression test; tests fail against the relevant old behavior.
* Keep fixture origin, engine version and generation command recorded; do not invent expected metric scores.
* CI runs the meaningful suite and retains useful failure evidence.

Evidence: docs/REPOSITORY_AUDIT.md, Build/test readiness.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"},{"id":"PLA-529","title":"Bound chart rendering and remove quadratic heatmap work"},{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"},{"id":"PLA-524","title":"Replace the 30 fps assumption with an authoritative frame-to-time map"},{"id":"PLA-523","title":"Harden process launch, progress parsing, diagnostics, and teardown"},{"id":"PLA-522","title":"Bind every result and export to immutable source and encode identities"},{"id":"PLA-521","title":"Make cancellation stop FFmpeg and prevent stale batch writes"}],"blockedBy":[{"id":"PLA-519","title":"Establish clean main, archive legacy branches, and verify macOS CI"}],"relatedTo":[],"duplicateOf":null}

## PLA-521: Make cancellation stop FFmpeg and prevent stale batch writes

Status: Todo

CA-01: VMAFBatchView.swift cancelBatch only clears flags; calculateVMAF keeps running and completion writes captured comparisons[idx]. Cancel→Clear can crash. Double Start during async validation and Cancel→Restart can overlap jobs; the delegate ownership cycle also needs cleanup.

Acceptance:

* Own Task/Process lifetime in one job service with preparing/running/cancelling/finished states.
* Capture inputs before the first await and update rows by stable item/run IDs.
* Cancel terminates and awaits the child, cleans resources and prevents stale progress/results.
* Cover Cancel→Clear/Remove/Restart, double Start, window closure and failed launch.
* No queue mutation can cause an index crash or relabel another run.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-541","title":"Turn batch results into fair source-versus-many encode decisions"},{"id":"PLA-537","title":"Add synchronized source/encode playback with exact frame navigation"},{"id":"PLA-523","title":"Harden process launch, progress parsing, diagnostics, and teardown"}],"blockedBy":[{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"}],"relatedTo":[],"duplicateOf":null}

## PLA-522: Bind every result and export to immutable source and encode identities

Status: Todo

CA-02: changing single selections leaves old results displayed; PDF reads global UserDefaults filenames. Changing a completed batch reference preserves completed results and skips recalculation.

Acceptance:

* Snapshot source/encode URLs/identities, streams and configuration for each run.
* UI/export labels derive from that snapshot, not current selections or global last-use settings.
* Input changes invalidate displayed results or explicitly display a past comparison.
* Changing batch reference resets affected jobs or starts a distinct batch.
* Tests cover A/B→A/C, selection during run, failed rerun, multiple windows, and mixed old/new batch rows.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-541","title":"Turn batch results into fair source-versus-many encode decisions"},{"id":"PLA-539","title":"Make exports responsive, practical, and reproducible"},{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"},{"id":"PLA-524","title":"Replace the 30 fps assumption with an authoritative frame-to-time map"}],"blockedBy":[{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"}],"relatedTo":[],"duplicateOf":null}

## PLA-523: Harden process launch, progress parsing, diagnostics, and teardown

Status: Backlog

CA-08/09/10: filter escaping fails valid punctuation paths; non-executable fallback joins filenames into /bin/sh -c. Human stderr parser misses normal fps=0.0/time= tokens and partial records. Diagnostics can leak from previous runs; failed launches/parses leak handlers or temp logs.

Acceptance:

* Process uses executableURL + argument array only; missing/non-executable helper fails clearly.
* Filter grammar escaping or controlled staged filenames handles Unicode, spaces, quotes, colons, commas, brackets and shell metacharacters.
* Machine-readable progress has incremental record buffering, actual evaluated coverage and indeterminate unknown duration.
* Per-run diagnostics reset before preflight; use LocalizedError or typed presentation.
* All success/failure/cancel paths drain/close resources and remove temporary logs; test arbitrary progress byte boundaries.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-525","title":"Enforce valid content correspondence and explicit end-of-stream behavior"}],"blockedBy":[{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"},{"id":"PLA-521","title":"Make cancellation stop FFmpeg and prevent stale batch writes"}],"relatedTo":[],"duplicateOf":null}

## PLA-524: Replace the 30 fps assumption with an authoritative frame-to-time map

Status: Backlog

CA-04: FrameMetric uses (frameNumber−1)/30 and result duration uses frameCount/30. Zero-based libvmaf frames give a negative first timestamp; 24/60 fps durations are wrong. libvmaf top-level fps is processing throughput, not source cadence.

Acceptance:

* Retain exact decoded PTS/time base or validated equivalent mapping for evaluated frame pairs.
* Normalized first frame starts at zero; 240 frames at 24 fps and 600 at 60 fps each cover 10 seconds.
* 24000/1001 and VFR mapping remains correct.
* Timeline, CSV/JSON/PDF and future playback share the same mapping.
* Tests distinguish source duration, compared coverage, final frame PTS and processing throughput.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-539","title":"Make exports responsive, practical, and reproducible"},{"id":"PLA-537","title":"Add synchronized source/encode playback with exact frame navigation"},{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"},{"id":"PLA-525","title":"Enforce valid content correspondence and explicit end-of-stream behavior"}],"blockedBy":[{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"},{"id":"PLA-522","title":"Bind every result and export to immutable source and encode identities"}],"relatedTo":[],"duplicateOf":null}

## PLA-525: Enforce valid content correspondence and explicit end-of-stream behavior

Status: Backlog

CA-03: only dimensions are validated. Independent setpts resets do not prove identical content. Default framesync can hold a short reference's last frame while scoring a longer encode.

Acceptance:

* Probe authoritative video streams, durations, timestamps, cadence, aspect/rotation and interlace.
* Define supported same-content comparisons and report actual compared coverage.
* Refuse unexplained edits, drops, cadence changes and unsupported interlace instead of emitting an ordinary quality verdict.
* Use explicit EOF policy with no hidden frame repetition.
* Known offsets/scaling require an explicit recorded policy; never normalize away a defect by default.
* Fixtures include identity, both unequal-duration directions, one-frame shift/drop, VFR, 24→30, rotated/non-square-pixel content.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-537","title":"Add synchronized source/encode playback with exact frame navigation"},{"id":"PLA-526","title":"Define SDR color and geometry normalization with an explicit HDR boundary"}],"blockedBy":[{"id":"PLA-523","title":"Harden process launch, progress parsing, diagnostics, and teardown"},{"id":"PLA-524","title":"Replace the 30 fps assumption with an authoritative frame-to-time map"}],"relatedTo":[],"duplicateOf":null}

## PLA-526: Define SDR color and geometry normalization with an explicit HDR boundary

Status: Backlog

The current engine supplies decoded samples to SDR models without a color/range/HDR contract. Extra metrics would amplify this uncertainty.

Acceptance:

* Persist matrix, primaries, transfer, range, bit depth, chroma siting, geometry and all transforms.
* Support a tested SDR comparison path; unknown metadata is a visible documented assumption or actionable refusal.
* Do not silently tone-map PQ/HLG into a native-HDR quality claim.
* If comparing smaller encodes, use an explicit viewing canvas/kernel and preserve original encode dimensions/precision; do not hide lost detail by quietly shrinking the reference.
* Full/limited range, chroma-only errors, 8/10-bit, PQ/HLG, rotated and mismatched aspect fixtures match documented policy.
* Preprocessing is shared by all metric adapters.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-543","title":"Investigate HDR and temporal perception with an explicit display model"},{"id":"PLA-537","title":"Add synchronized source/encode playback with exact frame navigation"},{"id":"PLA-533","title":"Add XPSNR as an independent distortion measurement"},{"id":"PLA-532","title":"Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine"}],"blockedBy":[{"id":"PLA-525","title":"Enforce valid content correspondence and explicit end-of-stream behavior"}],"relatedTo":[],"duplicateOf":null}

## PLA-527: Introduce a versioned metric/result schema and robust decoder

Status: Backlog

CA-11/13: result types are hardwired to legacy VMAF features; selected model and provenance are omitted. Mandatory Doubles and string-only aggregate fields reject valid null/numeric auxiliary metrics.

Acceptance:

* Represent metric identifier/version/model hash, direction, units/range, pooling, validity and analyzed coverage.
* Represent unavailable, undefined and infinite values safely in JSON; never zero-fill missing metrics or clamp signed scores.
* Require only selected primary outputs; retain unknown/optional features without breaking usable results.
* Include immutable input/stream identity, timestamps, preprocessing and engine/app versions.
* Legacy result import remains explicitly legacy/unknown where metadata cannot be reconstructed.
* Roundtrip fixtures cover null auxiliaries, numeric aggregates, extra fields, missing primary output, empty/truncated logs.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-539","title":"Make exports responsive, practical, and reproducible"},{"id":"PLA-534","title":"Expose source-aware CAMBI banding diagnostics"},{"id":"PLA-533","title":"Add XPSNR as an independent distortion measurement"},{"id":"PLA-532","title":"Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine"},{"id":"PLA-530","title":"Replace misleading Poor/Excellent colors with honest metric presentation"}],"blockedBy":[{"id":"PLA-522","title":"Bind every result and export to immutable source and encode identities"},{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"}],"relatedTo":[],"duplicateOf":null}

## PLA-528: Ship a reproducible native Apple Silicon analysis engine

Status: Todo

CA-06: checked-in FFmpeg is x86_64 only and requires Rosetta on Apple Silicon. Core filter hardcodes n_threads=99; fallback engine identity can vary.

Acceptance:

* Build/pin native arm64 FFmpeg/libvmaf with declared capabilities; make Intel support an explicit artifact decision.
* Record source revisions, build configuration, hashes, licenses/notices and matching source availability.
* Packaged app runs a short metric comparison without Rosetta, Homebrew or hidden dynamic libraries.
* Probe executable permissions, architecture, model resource paths, filter support and exact versions at build/package validation.
* Replace 99 threads with a bounded policy; collect throughput/memory/energy evidence before claiming improvements.
* Keep existing binary until a verified replacement is available; do not remove working resources speculatively.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-542","title":"Validate packaged releases and third-party provenance"},{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-533","title":"Add XPSNR as an independent distortion measurement"},{"id":"PLA-532","title":"Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine"},{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"}],"blockedBy":[{"id":"PLA-519","title":"Establish clean main, archive legacy branches, and verify macOS CI"}],"relatedTo":[],"duplicateOf":null}

## PLA-529: Bound chart rendering and remove quadratic heatmap work

Status: Todo

CA-05: heatMapColor repeatedly recomputes full-array min/max for each frame, causing O(N²) work. Both charts add 10 identical grid rules per frame; a 2-hour 30fps clip produces 2.16 million redundant rules.

Acceptance:

* Cache immutable summaries, draw grid once and use viewport-sized spike-preserving level of detail.
* Preserve all raw metrics for summaries/export; visualization decimation must not hide worst intervals.
* Binary-search timestamps for hover; bound axis ticks and cache viewport work.
* Exercise 216k and 1M synthetic points; record plotted mark counts, main-thread time, memory and interaction performance on a named Mac.
* Empty/one-frame/constant-score results render safely.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-530","title":"Replace misleading Poor/Excellent colors with honest metric presentation"}],"blockedBy":[{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"}],"relatedTo":[],"duplicateOf":null}

## PLA-530: Replace misleading Poor/Excellent colors with honest metric presentation

Status: Backlog

CA-07: current colors normalize to each clip's min/max and label endpoints Poor/Excellent, so 99.1 can be poor and 12 excellent. Constant-score clips divide by zero. This view is a temporal score plot, not a spatial artifact map.

Acceptance:

* Choose an explicitly relative scale or consistent metric-specific numeric scale.
* Equal scores have understandable behavior across clips; constant/empty domains are safe.
* Do not claim transparency or universal quality categories from uncalibrated cutoffs.
* Name temporal plots and spatial differences accurately.
* Keep metric units/direction/model and uncertainty discoverable without filling the default view with jargon.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-538","title":"Build a concise result workflow around savings and moments to review"}],"blockedBy":[{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"},{"id":"PLA-529","title":"Bound chart rendering and remove quadratic heatmap work"}],"relatedTo":[],"duplicateOf":null}

## PLA-531: Create a licensed, reproducible adversarial comparison corpus

Status: Backlog

Establish correctness and characterize blind spots before asserting holistic quality. Start with small synthetic fixtures plus 12–20 short licensed scenes spanning live action, anime, grain, gradients, foliage, text, dark content and high motion.

Acceptance:

* Manifest includes source URL/license, checksum, clip extraction and distortion-generation commands; large media stays out of ordinary Git.
* Matrix includes identity/lossless, AVC/HEVC/AV1 ladders, sharpen/contrast/denoise attacks, luma-preserving color damage, banding/dither, offsets/drops/freezes, resize/crop and HDR boundaries.
* Compare adapters to pinned upstream outputs with justified tolerance and correct input orientation.
* Record disagreements and exceptions; do not require strict score monotonicity or tune tests to pass.
* Small randomized visual review validates useful scene selection; do not require a full new subjective research program to ship.
* Keep calibration and held-out scenes separate if thresholds/composites are later learned.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-544","title":"Evaluate a clearly labeled quick scan without overstating coverage"},{"id":"PLA-543","title":"Investigate HDR and temporal perception with an explicit display model"},{"id":"PLA-534","title":"Expose source-aware CAMBI banding diagnostics"},{"id":"PLA-533","title":"Add XPSNR as an independent distortion measurement"},{"id":"PLA-532","title":"Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine"}],"blockedBy":[{"id":"PLA-528","title":"Ship a reproducible native Apple Silicon analysis engine"},{"id":"PLA-520","title":"Replace template-only coverage with analysis regression seams"}],"relatedTo":[],"duplicateOf":null}

## PLA-532: Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine

Status: Backlog

VMAF v1.0.16 models released June 2026 add chroma/banding features, default NEG behavior and revised motion handling. libvmaf 3.2.0 announces initial support, while ffmpeg-quality-metrics documents needing a newer build for its FFmpeg path; resolve with execution, not version guessing.

Acceptance:

* Pin and smoke-test exact FFmpeg/libvmaf/models tuple on arm64.
* Upstream parity for tested 10-bit SDR processing; carry original encode width/height/bitdepth into CAMBI.
* Choose explicit viewing/HFR profiles, with model identity/range in results. Fix legacy max-dimension≥2160 rule that misclassifies 1440p.
* Preserve legacy comparisons and label any v0.6.1 NEG fallback.
* No universal 0–100 clamp; some v1 profiles can exceed 100.
* Document unsupported HDR and model limitations.

Sources: [https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md](<https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md>) ; [https://github.com/Netflix/vmaf/releases/tag/v3.2.0](<https://github.com/Netflix/vmaf/releases/tag/v3.2.0>) ; [https://github.com/slhck/ffmpeg-quality-metrics#specifying-vmaf-model](<https://github.com/slhck/ffmpeg-quality-metrics#specifying-vmaf-model>)

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"},{"id":"PLA-534","title":"Expose source-aware CAMBI banding diagnostics"}],"blockedBy":[{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"},{"id":"PLA-528","title":"Ship a reproducible native Apple Silicon analysis engine"},{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"},{"id":"PLA-526","title":"Define SDR color and geometry normalization with an explicit HDR boundary"}],"relatedTo":[],"duplicateOf":null}

## PLA-533: Add XPSNR as an independent distortion measurement

Status: Backlog

Use upstream FFmpeg XPSNR alongside VMAF. Preserve per-plane/per-frame results and upstream aggregation, with named units.

Acceptance:

* Input orientation is [reference][distorted], unlike usual libvmaf [distorted][reference]; test with an asymmetric fixture.
* Same validated normalization/correspondence as other adapters.
* Store Y/U/V and documented aggregate; minimum plane average is not described as worst-frame score.
* Identity/infinity and color-only damage fixtures roundtrip correctly.
* Compare against pinned CLI output and benchmark added cost.
* Keep dB separate from VMAF axes; do not average it into a invented 100-point score.

Source: [https://ffmpeg.org/ffmpeg-filters.html#xpsnr-1](<https://ffmpeg.org/ffmpeg-filters.html#xpsnr-1>)

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"},{"id":"PLA-535","title":"Evaluate and integrate SSIMULACRA2 as optional deeper analysis"}],"blockedBy":[{"id":"PLA-528","title":"Ship a reproducible native Apple Silicon analysis engine"},{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"},{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"},{"id":"PLA-526","title":"Define SDR color and geometry normalization with an explicit HDR boundary"}],"relatedTo":[],"duplicateOf":null}

## PLA-534: Expose source-aware CAMBI banding diagnostics

Status: Backlog

Expose banding information with source context. VMAF v1 already incorporates CAMBI, so a diagnostic view is not an independent extra vote.

Acceptance:

* Retain reference, encode and upstream full-reference max(0,distorted−reference) results.
* Preserve original bit depth/dimensions and relevant EOTF configuration.
* Identically banded source/encode does not appear as newly introduced banding.
* Validate gradients, dark skies, 10→8-bit and dither fixtures against upstream.
* Time-localize findings; generate correctly labeled heatmaps on demand if supported.
* Do not call raw subtraction perfect causal attribution or treat SDR metric capability as validated HDR quality.

Source: [https://github.com/Netflix/vmaf/blob/master/resource/doc/cambi.md](<https://github.com/Netflix/vmaf/blob/master/resource/doc/cambi.md>)

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"},{"id":"PLA-535","title":"Evaluate and integrate SSIMULACRA2 as optional deeper analysis"}],"blockedBy":[{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"},{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"},{"id":"PLA-532","title":"Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine"}],"relatedTo":[],"duplicateOf":null}

## PLA-535: Evaluate and integrate SSIMULACRA2 as optional deeper analysis

Status: Backlog

SSIMULACRA2 adds a different color-aware perceptual image measurement. It is framewise, can be negative, and is not a complete temporal video model. This increment must not block Standard VMAF/XPSNR/CAMBI delivery.

Acceptance:

* Pin upstream libjxl/native helper and retain dependency notices.
* Feed explicitly managed high-precision decoded frames; verify linear-sRGB conversion against reference executable.
* Test negative scores, metadata differences, color-only damage, cancellation and bounded buffers.
* Benchmark real Apple Silicon throughput, memory and energy before enabling by default.
* Keep metric mode separate from sampling coverage; no screenshot/8-bit roundtrip shortcut.
* Do not transfer still-image quality labels into universal video claims.

Sources: [https://github.com/cloudinary/ssimulacra2](<https://github.com/cloudinary/ssimulacra2>) ; [https://github.com/libjxl/libjxl/blob/main/tools/ssimulacra2.cc](<https://github.com/libjxl/libjxl/blob/main/tools/ssimulacra2.cc>)

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[],"blockedBy":[{"id":"PLA-534","title":"Expose source-aware CAMBI banding diagnostics"},{"id":"PLA-533","title":"Add XPSNR as an independent distortion measurement"}],"relatedTo":[],"duplicateOf":null}

## PLA-536: Find weak intervals and metric disagreements without an invented composite

Status: Backlog

A whole-video mean hides brief or sustained damage. Build an inspectable summary with native metric aggregates plus supplementary distributions.

Acceptance:

* Higher-is-better metrics retain mean/median/P5/min; lower-is-better diagnostics use the appropriate upper tail.
* Preserve upstream pooling and label supplementary statistics separately; no harmonic mean of signed metrics.
* Distinguish isolated frames from contiguous bad windows, using actual duration for VFR.
* Merge nearby/overlapping findings into a small review list; retain metric/reason provenance.
* Independent metric disagreement is a review cue, not an averaged-away discrepancy.
* Missing metrics/partial coverage never produce a falsely complete report.
* Synthetic brief, sustained and competing-metric defects select deterministic correct intervals.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-544","title":"Evaluate a clearly labeled quick scan without overstating coverage"},{"id":"PLA-539","title":"Make exports responsive, practical, and reproducible"},{"id":"PLA-538","title":"Build a concise result workflow around savings and moments to review"}],"blockedBy":[{"id":"PLA-533","title":"Add XPSNR as an independent distortion measurement"},{"id":"PLA-524","title":"Replace the 30 fps assumption with an authoritative frame-to-time map"},{"id":"PLA-532","title":"Validate VMAF v1 and explicit viewing profiles on the shipped Mac engine"},{"id":"PLA-534","title":"Expose source-aware CAMBI banding diagnostics"}],"relatedTo":[],"duplicateOf":null}

## PLA-537: Add synchronized source/encode playback with exact frame navigation

Status: Backlog

Deliver the core visual evidence missing from the current score-only app. Reuse authoritative frame mapping and color policy; an ordinary AVPlayer preview alone may not cover all FFmpeg-supported formats.

Acceptance:

* Shared play/pause/seek/loop/frame-step across matched source/encode frames.
* Wipe or side-by-side view, synchronized 1:1 zoom/pan and clear reference labels.
* Every selected metric concern lands on its exact interval/frame pair.
* Decode support and color rendering are explicit; unsupported native-player codecs have a deliberate fallback/error.
* Difference maps are named by computation and gain, not presented as human-annoyance heatmaps.
* Long/GOP-heavy/VFR/rotated clips remain aligned while analysis runs; test actual Mac playback.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-538","title":"Build a concise result workflow around savings and moments to review"}],"blockedBy":[{"id":"PLA-526","title":"Define SDR color and geometry normalization with an explicit HDR boundary"},{"id":"PLA-524","title":"Replace the 30 fps assumption with an authoritative frame-to-time map"},{"id":"PLA-521","title":"Make cancellation stop FFmpeg and prevent stale batch writes"},{"id":"PLA-525","title":"Enforce valid content correspondence and explicit end-of-stream behavior"}],"relatedTo":[],"duplicateOf":null}

## PLA-538: Build a concise result workflow around savings and moments to review

Status: Backlog

Product goal: show what changed, where, and how much space was saved. Framewise and other tools already cover native/multi-metric comparison, so usefulness and trust must differentiate BetterVMAF.

Acceptance:

* Default flow is choose source/encode → analyze → inspect a short concern list on one timeline.
* Show size/bitrate tradeoff separately from named quality measurements; never claim “95% retained quality” from VMAF 95.
* Metric detail, viewing assumptions and diagnostics are progressively disclosed.
* Drag/drop, keyboard navigation and accessibility remain native and useful.
* Each concern directly seeks the viewer; adjacent duplicate findings are grouped.
* Run a small fixed-task comparison against Framewise/video-compare when available, reporting limitations fairly.

Source: docs/PRODUCT_DIRECTION.md.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-542","title":"Validate packaged releases and third-party provenance"},{"id":"PLA-541","title":"Turn batch results into fair source-versus-many encode decisions"}],"blockedBy":[{"id":"PLA-530","title":"Replace misleading Poor/Excellent colors with honest metric presentation"},{"id":"PLA-537","title":"Add synchronized source/encode playback with exact frame navigation"},{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"}],"relatedTo":[],"duplicateOf":null}

## PLA-539: Make exports responsive, practical, and reproducible

Status: Backlog

CA-12: CSV/JSON construction and PDF drawing run synchronously on the main actor. Defaults can generate thousands of PDF pages; PDF ignores includeAggregateMetrics. Results omit reproducibility metadata.

Acceptance:

* Choose output/options before expensive work; serialize off the main actor and bound/cancel lengthy exports.
* Summary PDF is a practical default; full frame data belongs in CSV/JSON or explicit detailed export.
* Honor every option; preserve immutable source identities and full schema/configuration in JSON.
* Include versioned metric units, selected model, input/stream hashes, timestamps, transforms and analyzed coverage.
* Large-result export leaves UI responsive and handles failure/cancellation without partial-success claims.
* Roundtrip and snapshot fixtures verify identities, timestamps, nonfinite values and selected fields.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-542","title":"Validate packaged releases and third-party provenance"}],"blockedBy":[{"id":"PLA-524","title":"Replace the 30 fps assumption with an authoritative frame-to-time map"},{"id":"PLA-522","title":"Bind every result and export to immutable source and encode identities"},{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"},{"id":"PLA-527","title":"Introduce a versioned metric/result schema and robust decoder"}],"relatedTo":[],"duplicateOf":null}

## PLA-540: Measure and enforce Apple Silicon responsiveness and resource budgets

Status: Backlog

Native UI and native binaries alone do not prove smoothness or low battery use. Record a real baseline before selecting budgets.

Acceptance:

* Benchmark named Apple Silicon hardware with 1080p/4K, 8/10-bit, 24/60fps and long result sets.
* Capture decode/metric throughput separately, first-result latency, peak RSS, cancel latency and CPU/GPU/energy observations.
* Measure UI frame pacing/interaction while analysis and export run; avoid per-frame main-actor updates.
* Bound concurrent jobs, decoded buffers, logs, thumbnails and heatmap caches.
* Verify hardware/software decode parity before changing decode defaults.
* Optimize measured hotspots; keep reproducible commands and measured before/after evidence.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[{"id":"PLA-544","title":"Evaluate a clearly labeled quick scan without overstating coverage"},{"id":"PLA-543","title":"Investigate HDR and temporal perception with an explicit display model"},{"id":"PLA-542","title":"Validate packaged releases and third-party provenance"},{"id":"PLA-541","title":"Turn batch results into fair source-versus-many encode decisions"}],"blockedBy":[{"id":"PLA-529","title":"Bound chart rendering and remove quadratic heatmap work"},{"id":"PLA-537","title":"Add synchronized source/encode playback with exact frame navigation"},{"id":"PLA-523","title":"Harden process launch, progress parsing, diagnostics, and teardown"},{"id":"PLA-528","title":"Ship a reproducible native Apple Silicon analysis engine"}],"relatedTo":[],"duplicateOf":null}

## PLA-541: Turn batch results into fair source-versus-many encode decisions

Status: Backlog

Existing batch mode addresses public GitHub issue #2 but has provenance/lifecycle hazards and lacks a clear comparable-results model. Preserve the useful workflow after foundational repairs.

Acceptance:

* One immutable reference with stable independently cancellable encode jobs.
* Queue can resume/retry failed work without mixing references/configurations.
* Compare file size/bitrate and quality profiles only when preprocessing/model/coverage are compatible.
* Show tradeoffs and non-dominated choices without a fake universal quality-efficiency score.
* Selecting a candidate opens the same exact visual inspection workflow.
* Overnight batch has bounded resources and useful failure recovery.

Public request: [https://github.com/oliverdougherC/BetterVMAF/issues/2](<https://github.com/oliverdougherC/BetterVMAF/issues/2>) (already closed; retain as linked product evidence).

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[],"blockedBy":[{"id":"PLA-521","title":"Make cancellation stop FFmpeg and prevent stale batch writes"},{"id":"PLA-522","title":"Bind every result and export to immutable source and encode identities"},{"id":"PLA-538","title":"Build a concise result workflow around savings and moments to review"},{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"}],"relatedTo":[],"duplicateOf":null}

## PLA-542: Validate packaged releases and third-party provenance

Status: Backlog

Existing package script does not prove bundled-engine execution, clean-machine operation or release provenance. Binary strings show GPL/version3 options; the app's MIT license is not a license for the entire dependency bundle.

Acceptance:

* Versioned app/DMG/release metadata agrees.
* Package contains pinned models, native helper(s), notices, source/build provenance and checksums.
* Clean Mac smoke without Homebrew/Rosetta for arm64 covers identity comparison, real inputs, cancellation and export.
* Decide supported macOS/Intel matrix explicitly and test each claimed target.
* Document local unsigned distribution versus any chosen Developer ID/notarized path; do not require a paid account just for development.
* Prefer stable required build/test checks on main when repository settings are available.
* Keep this task open until real packaged-app evidence exists.

Source: [https://ffmpeg.org/legal.html](<https://ffmpeg.org/legal.html>)

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[],"blockedBy":[{"id":"PLA-539","title":"Make exports responsive, practical, and reproducible"},{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-528","title":"Ship a reproducible native Apple Silicon analysis engine"},{"id":"PLA-538","title":"Build a concise result workflow around savings and moments to review"}],"relatedTo":[],"duplicateOf":null}

## PLA-543: Investigate HDR and temporal perception with an explicit display model

Status: Backlog

Later bounded research: evaluate current HDR-capable VMAF availability and ColorVideoVDP, which documents color/time/HDR handling and Apple Silicon MPS. Neither is evidence of acceptable native app cost yet.

Acceptance:

* Verify current upstream models/licenses at implementation time.
* Define display luminance/gamut/transfer/viewing assumptions and source/encode correspondence.
* Compare PQ/HLG and temporal artifact fixtures against reference implementation.
* Measure Mac runtime/package/memory/energy cost including PyTorch/MPS deployment.
* Decide feasible integration or explicit deferral with evidence.
* No silent tone-map-to-SDR result is labeled native HDR quality; no new metric is claimed immune to gaming.

Source: [https://github.com/gfxdisp/ColorVideoVDP](<https://github.com/gfxdisp/ColorVideoVDP>)

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[],"blockedBy":[{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-526","title":"Define SDR color and geometry normalization with an explicit HDR boundary"},{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"}],"relatedTo":[],"duplicateOf":null}

## PLA-544: Evaluate a clearly labeled quick scan without overstating coverage

Status: Backlog

Ship one full Standard analysis first. Sampling is later optimization and must not be confused with the choice of metrics.

Acceptance:

* Record exact selected frames/intervals, deterministic seed/method and analyzed coverage.
* Preserve necessary temporal neighbors/cadence for motion-aware metrics.
* Evaluate stratified/scene-aware sampling and expansion near defects; fixed stride can miss periodic artifacts.
* Compare brief/periodic/sustained defect discovery against full analysis.
* Label sampled distributions as sampled; do not claim global worst frame or fabricated confidence interval.
* Keep full results reproducible and keep UI choices minimal.

Planning basis: [source audit](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/REPOSITORY_AUDIT.md>) and [quality strategy](<https://github.com/oliverdougherC/BetterVMAF/blob/main/docs/QUALITY_STRATEGY.md>), researched 2026-09-13. Code findings reference baseline `209921c` unless noted.

Dependencies: {"blocks":[],"blockedBy":[{"id":"PLA-540","title":"Measure and enforce Apple Silicon responsiveness and resource budgets"},{"id":"PLA-536","title":"Find weak intervals and metric disagreements without an invented composite"},{"id":"PLA-531","title":"Create a licensed, reproducible adversarial comparison corpus"}],"relatedTo":[],"duplicateOf":null}


