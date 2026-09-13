# BetterVMAF historical source audit

This document preserves the foundation audit as historical evidence. The current implementation addresses these findings; see [VALIDATION.md](VALIDATION.md) for the issue-by-issue status, native results and remaining limitations. Environment statements below describe the original audit, not the Apple Silicon integration session.

Audited baseline main `209921cd525e4331b361bf78c428787fe3e6f946` on 2026-09-13. File/line references below describe that commit. This is a source audit, not a claim of macOS runtime acceptance. The accompanying foundation cleanup adds shared build/test configuration, removes tracked user state, improves packaging, and corrects documentation. Application behavior findings below remain planned repairs in Linear. The environment is Linux, has no Swift/Xcode, and its system FFmpeg lacks libvmaf. Findings below are source-traced; portable FFmpeg parser/progress checks and binary inspection were actually executed where stated.

## Highest-priority findings

### CA-01 — P1: Cancel exposes a mutable batch while the old task still writes array indices

**References:** `VMAF/VMAFBatchView.swift:191-240,241-260,264-268`, queue editing at `62-84`; `VMAF/VMAFCalculator.swift:337-391`.

`cancelBatch()` only sets `isRunning = false` and clears `currentIndex`. The active FFmpeg process is local to `calculateVMAF` and continues through `waitUntilExit()`. Cancel immediately enables Clear, removal, a new reference, and Start Batch. The old completion then writes `comparisons[idx]` without a bounds or run-identity check. A user can start a long analysis, Cancel, Clear, and receive an out-of-bounds crash when FFmpeg completes. Cancel followed by Start can run two FFmpeg processes through the same mutable calculator; stale progress and completions can update the new batch. Validation also happens before `isRunning` is set, so double Start or editing during asynchronous validation has the same index-staleness problem.

The delegate is strong and stores the view struct, which itself holds the calculator; assigning `calculator.delegate = self` creates a calculator → delegate view → calculator ownership cycle. No task handle, process cancellation, or delegate cleanup is present.

**Acceptance:** Use a stable job owner and immutable input snapshot, stable item IDs and run IDs, and an explicit preparing/running/cancelling/finished state. Disable conflicting edits before the first await. Cancel must terminate and await the process, drain/close its pipes, clean temp files, and prevent all subsequent callbacks from changing a newer run. Cover Cancel→Clear, Cancel→Remove, Cancel→Restart, double Start during validation, and closing the window with an active process. Include a real process test as well as deterministic lifecycle tests.

### CA-02 — P1: Results can become attached to different input videos, including in exported PDFs

**References:** `VMAF/ContentView.swift:88-119,179-255,337-353,356-392`; `VMAF/VMAFBatchView.swift:157-166,191-203`; `VMAF/ExportManager.swift:85-100`; result model `VMAF/VMAFCalculator.swift:14-22`.

Single mode leaves input Select buttons enabled during a job and never clears the old result on selection or the start/failure of another calculation. A completed A-vs-B score therefore remains under A-vs-C filenames, or appears after changing inputs mid-run. PDF export takes filenames from global `UserDefaults` last-selection keys rather than the result's actual inputs, so this mismatch is written into a durable report. Separate app windows can overwrite the same keys. In batch mode, changing the reference after a batch completes leaves every old completed result intact, and the next run skips them because it only processes non-completed items. A mixed batch can silently contain results from different references.

**Acceptance:** Results contain immutable reference/comparison identities and analysis configuration. UI and every export display those identities. Changing inputs must invalidate results or clearly show them as a separate past run. Changing a batch reference resets/invalidate completed rows or starts a new batch. Add A/B→A/C selection, failed rerun, two-window export, and reference-change batch tests.

### CA-03 — P1: The comparison contract accepts duration/cadence/color mismatches and produces a score anyway

**References:** `VMAF/VMAFCalculator.swift:178-197,281-316`; `VMAF/VMAFBatchView.swift:270-303`.

Preflight validates only transformed dimensions. Batch loads nominal FPS but does not use it. Neither path checks duration, timestamp continuity, frame correspondence, sample aspect ratio, interlace, color primaries/transfer/range, or HDR. The filter graph only subtracts each stream's initial PTS and sends decoded samples directly to the SDR v0.6.1/4K model. It has no explicit EOF policy. FFmpeg's libvmaf uses framesync with distorted frames as the primary stream; default secondary EOF handling repeats the last reference frame. Thus a shorter reference can be held while the longer comparison keeps being scored, and a shorter comparison silently reduces evaluated coverage. A cadence conversion, missing frame, offset edit, or HDR/SDR pair can be presented as an ordinary quality result without qualification.

This is a correctness prerequisite for additional metrics, not just a missing advanced setting. Prefer rejecting unsupported conditions in the initial release over silently normalizing away damage the app is intended to measure.

**Acceptance:** One documented comparison policy shared by batch/single/export. Probe authoritative stream metadata; define evaluated coverage and timestamp matching; reject unexplained duration/cadence mismatch, unsupported HDR/interlace, and ambiguous color interpretation. Explicitly handle EOF without padding hidden inside the score. Report any intentional scaling, crop, alignment, or color conversion as part of the analysis configuration. Fixtures: identical content, one-frame offset/drop, unequal durations both directions, 24↔30 conversion, VFR, full/limited range, BT.709/PQ/HLG metadata, non-square pixels, and rotated files. Verify expected refusal or explicit aligned coverage, not merely successful FFmpeg exit.

**Primary evidence:** [FFmpeg libvmaf implementation](https://github.com/FFmpeg/FFmpeg/blob/n8.0/libavfilter/vf_libvmaf.c) lines 137-147 and 504-512; [framesync implementation](https://github.com/FFmpeg/FFmpeg/blob/n8.0/libavfilter/framesync.c) lines 372-387; [documented framesync defaults](https://ffmpeg.org/ffmpeg-filters.html#Options-for-filters-with-several-inputs-_0028framesync_0029).

### CA-04 — P1: All timelines and frame exports assume 30 fps, with an additional negative first timestamp

**References:** `VMAF/VMAFCalculator.swift:47-50,446-448`; `VMAF/ExportManager.swift:41,65`; `VMAF/PDFGenerator.swift:174`; chart domains `VMAF/VMAFGraphView.swift:17-22`, `VMAF/HeatMapView.swift:16-21`.

`timestamp = (frameNumber - 1) / 30` and `duration = frameCount / 30`. libvmaf JSON frame numbers start at zero, so the first frame is exported as -0.03333 seconds. A 10-second 60 fps source is reported as 20 seconds, and a 10-second 24 fps source as 8 seconds. This invalidates the proposed click-to-inspect workflow unless corrected before adding it. The libvmaf top-level `fps` is processing throughput, so using that field would not fix this.

**Acceptance:** Preserve decoded presentation timestamps/time bases or an explicit validated frame-to-time map from the exact evaluated stream. First timestamp is zero for normalized inputs; 240 frames at 24 fps and 600 at 60 fps each cover 10 seconds; 24000/1001 and VFR retain correct mapping. Charts, CSV/JSON, PDF, and eventual player navigation agree. [Zero-based libvmaf output loop](https://github.com/Netflix/vmaf/blob/v3.0.0/libvmaf/src/output.c), lines 141-156.

### CA-05 — P1: Heatmap rendering does quadratic work; charts produce millions of redundant marks on long clips

**References:** `VMAF/HeatMapView.swift:42-45,54-68,279-280`; `VMAF/VMAFGraphView.swift:37-48,57-79,85,220-225,296-322`; `VMAF/HeatMapView.swift:328-349`.

Every heatmap point calls `heatMapColor`; each call evaluates `yAxisRange` multiple times, and each `yAxisRange` scans the full frame array for min and max. A full N-frame plot performs O(N²) work before considering Swift Charts cost. Both chart bodies create 10 identical horizontal `RuleMark`s **inside each frame's closure**. A two-hour 30 fps result therefore requests about 2.16 million duplicate grid marks plus 216k data marks (432k for line + points), without downsampling. Every hover rebuild can also filter/scan the full array, and nearest-frame lookup maps the full visible set. One-second axis ticks generate thousands of labels. No device profiling was possible, so this report does not invent a measured frame rate; the algorithmic growth is directly visible.

**Acceptance:** Compute/cached summaries once, place grid marks outside the frame loop, render a viewport-sized min/max envelope or equivalent spike-preserving level of detail, and use timestamp binary search for hover. Keep raw data untouched for metrics and export. Profile 216k and 1M synthetic samples on an Apple Silicon Mac: bounded plotted mark count, smooth hover/zoom/scroll, no O(N²) color calculation, measured main-thread/energy/memory budget. Benchmark current baseline before selecting a concrete interaction latency target.

### CA-06 — P1: The shipped metric engine is Intel-only despite the native Mac goal

**References:** `VMAF/Resources/ffmpeg`; `VMAF/VMAFCalculator.swift:250-278,316`.

Actually executed `file VMAF/Resources/ffmpeg`: `Mach-O 64-bit x86_64 executable`; this is not a universal binary and contains no arm64 slice. Binary strings identify FFmpeg 8.0.1-tessus and an x86 build configuration. The core analysis therefore requires Intel execution/Rosetta on Apple Silicon rather than using an arm64 metric engine. `n_threads=99` also hardcodes a large worker count regardless of machine, memory, other analyses, or power mode.

**Acceptance:** Provide reproducible/pinned native arm64 engine artifacts and an explicit Intel-support decision. Run a packaged-app metric smoke on Apple Silicon without Rosetta and without Homebrew; inspect architecture, linked libraries, models, executable permissions, and engine version/hash. Benchmark an automatic or bounded concurrency policy rather than hardcoded 99. This finding does not assert a measured Rosetta slowdown or recommend unsupported GPU acceleration.

## Other actionable findings

### CA-07 — P2: Quality colors are clip-relative but labeled as absolute judgments

**References:** `VMAF/HeatMapView.swift:42-45,190-203,279-312`.

Colors normalize to the min/max of the current clip, and the legend labels that minimum Poor and maximum Excellent. A range 99.1–99.5 paints 99.1 red/poor; a range 10–12 paints 12 blue/excellent. Identical score values can change color when one unrelated frame changes the range. If every score is equal, normalization divides by zero and falls through to excellent blue. The current view is also a colored time/score scatterplot, not a spatial artifact heatmap.

**Acceptance:** Use a clearly labeled relative scale or a consistent numeric scale with carefully scoped interpretation; handle zero-width/empty domains. Do not conflate a temporal quality plot with a pixel error map. Tests compare identical values across result sets and constant-valued clips.

### CA-08 — P2: Progress parser does not parse normal FFmpeg FPS/time tokens or chunk boundaries

**References:** `VMAF/VMAFCalculator.swift:376-384,472-511`; single-mode use `VMAF/ContentView.swift:432-439`.

The parser only accepts tokens exactly equal to `fps=` or `time=` followed by another token. A real local FFmpeg run produced `frame=   30 fps=0.0 ... time=00:00:00.96`, so normal FPS and time values are skipped. FFmpeg's updates use carriage returns, but the code splits only newlines and never retains partial records between pipe reads. Large `frame=100000` counters also fail the required exact `frame=` token. The unknown-duration fallback divides seconds by a placeholder 100, then the UI treats that value as a percentage and divides by 100 again.

**Acceptance:** Consume machine-readable `-progress` records on a dedicated stream, buffer partial records, and use actual evaluated duration/frame counts. Unknown duration stays indeterminate. Test arbitrary byte splits, CR/LF, large frame counts, zero/unknown duration, and final `progress=end`.

### CA-09 — P2: Filter-path escaping fails legitimate paths; shell fallback is unsafe and ineffective

**References:** `VMAF/VMAFCalculator.swift:199-205,314-316,360-366`.

The helper does not escape comma, semicolon, brackets, or both FFmpeg parser layers. I executed its exact transformation against a Linux FFmpeg two-input `ssim=stats_file=...` filter, which uses the same graph/option parser: ordinary and space-containing paths passed; comma, brackets, colon, and apostrophe paths failed. An app/model in such a valid folder can therefore fail analysis. If FFmpeg loses its execute bit, the fallback concatenates all arguments unquoted into `/bin/sh -c`; the bundled app path already contains a space, and filenames can be interpreted as shell syntax. Invoking a non-executable Mach-O through a shell does not restore execute permission.

**Acceptance:** Always launch the process with argument arrays, fail clearly on missing/non-executable artifacts, and correctly escape the FFmpeg filter grammar (or eliminate path interpolation using a controlled working directory/safe staged model name). Integration cases include spaces, Unicode, apostrophe, colon, comma, semicolon, brackets and shell metacharacters without executing arbitrary input as shell code.

### CA-10 — P2: Diagnostic state leaks across runs, custom errors lose their helpful description, and failure paths leak logs

**References:** `VMAF/VMAFCalculator.swift:281-298,387-438,459-469,547-581`; `VMAF/ContentView.swift:385-389,407-424`.

Diagnostics reset only after both metadata reads, resolution validation, and model resolution. If a previous process failed and the next input fails preflight, the UI includes the previous command/stderr/status beside the new error. `VMAFError` conforms to `Error` and defines its own `localizedDescription`, but the catch variable is typed `Error`; it does not implement the `LocalizedError.errorDescription` bridge, so the primary UI receives generic domain/code text for these cases. Temp logs are removed only after successful JSON decoding, not through `defer`. File readability handlers likewise are not cleared if `process.run()` throws.

**Acceptance:** Fresh diagnostic context per job before preflight; `LocalizedError` or a typed presentation mapper; teardown on every exit. Tests cover missing track/model, resolution mismatch following an FFmpeg failure, invalid JSON, launch failure and cancellation, with no stale details or orphan files/handlers.

### CA-11 — P2: Model selection confuses 1440p/wide frames with 4K and is not recorded in results

**References:** `VMAF/VMAFCalculator.swift:193-197,294,14-22`.

The rule is `max(width,height) >= 2160`. A normal 2560×1440 input selects `vmaf_4k_v0.6.1`; 1920×1080 selects the default. Model calibration depends on viewing assumptions, not simply exceeding 2160 on the longest dimension. The selected model is also absent from stored/exported results. Resolve policy with the metric research rather than replacing one unsupported threshold with another.

**Acceptance:** Explicit documented analysis/viewing profile with model identifier/version/hash in results and exports; 1080p, 1440p, 2160p, portrait and ultrawide cases have intentional behavior. No silent unexplained change of score scale caused by a threshold.

### CA-12 — P2: Long exports run synchronously on the main actor and omit reproducibility metadata

**References:** `VMAF/ExportOptionsView.swift:70-98`; `VMAF/ExportManager.swift:35-101`; `VMAF/PDFGenerator.swift:109-193`; result schema `VMAF/VMAFCalculator.swift:14-22`.

The Task created within `@MainActor exportData()` synchronously builds CSV strings, allocates JSON dictionaries, or renders all PDF pages before showing the save panel. Selecting Export for a long result can block main-actor UI for the whole operation; the spinner cannot meaningfully animate during that work. Frame data and graphs default on, so the default PDF can generate thousands of raster pages for a movie. CSV/JSON omit source identities, engine/model versions, preprocessing, duration, frame count and schema version. PDF ignores `includeAggregateMetrics` and always prints summary results.

**Acceptance:** Choose the destination/options before expensive work, serialize data away from the main actor, and bound/render PDF work with responsive progress/cancel. Use a practical summary-PDF default and an explicit full data format for frame-level exports. Adopt a versioned typed result/export schema retaining provenance and analysis configuration; verify actual export options, roundtrip/schema fixtures, and large-result responsiveness.

### CA-13 — P2: Metric JSON decoding assumes every numeric diagnostic is finite and present

**References:** `VMAF/VMAFCalculator.swift:73-95,135-164,430-435`.

All feature/pooled values are mandatory `Double`, and aggregate metric values are declared `[String:String]`. Upstream libvmaf explicitly emits JSON `null` for nonfinite values and emits numeric aggregate values. A valid result containing an undefined auxiliary feature or future numeric aggregate fails the entire decode even when the requested VMAF score is usable. Current model output normally has an empty aggregate map; this is a verified format-contract incompatibility, not a claim that all current analyses fail. I checked v3.0.0 source and confirmed the currently-required integer motion/ADM scale features are in fact emitted by default; **do not file a generic missing-default-features bug**.

**Acceptance:** Preserve absent/undefined metrics as such, never zero-fill, require only the selected result metrics, and decode numeric aggregate values. Include fixture logs from the exact shipped engine plus null auxiliary features, unknown additional metrics, missing primary metric, empty frames and truncated JSON. [libvmaf JSON writer](https://github.com/Netflix/vmaf/blob/v3.0.0/libvmaf/src/output.c), lines 166-180, 201-235.

## Build/test readiness

- `VMAFTests/VMAFTests.swift:13-15` contains one empty `example()` with no assertion. UI tests only launch, measure launch, and capture a screenshot (`VMAFUITests/VMAFUITests.swift:25-40`, `VMAFUITestsLaunchTests.swift:20-31`). There are no analysis, preprocessing, cancellation, decoder, export, or correctness fixtures.
- `VMAF.xcodeproj/project.pbxproj:327,387` sets macOS **15.2**, but README says **13.0**. Decide supported minimum deliberately and test it; changing documentation alone is the honest current-state correction.
- Project uses Swift 5 language mode (`project.pbxproj:428,464`), app sandbox and hardened runtime enabled (`407-410,443-446`). No SwiftPM package exists. No native build/test result can be claimed from this Linux environment.
- On the audited commit no CI workflow/shared scheme/contributor/test guidance is present in tracked source. The accompanying foundation cleanup addresses repository hygiene and branch reconciliation; consult GitHub Actions for its actual CI result.
- `create_dmg.sh` only builds/copies/packages; it does not validate the bundled engine/model or run tests. A packaged-app identity-pair smoke is higher value than another launch-only UI test.
- Binary inspection shows `--enable-gpl --enable-version3` in the bundled FFmpeg. The repository has only its app MIT license and no tracked engine-source provenance/build recipe/notices. Have the distribution plan preserve the actual third-party licensing/source obligations; do not imply the whole bundled distribution is MIT. This is a packaging/provenance task, not a legal conclusion from the audit.

## Suggested implementation order

1. Repository baseline and macOS build/packaged smoke.
2. Job/process ownership and cancellation; immutable result provenance.
3. Comparison preflight, timing, color/range/HDR policy; schema/fixture tests.
4. Native arm64 engine and resource/concurrency packaging.
5. Bounded chart rendering and correct quality presentation.
6. Additional metrics and synchronized visual inspection over the stable comparison contract.
7. Responsive reproducible export, performance calibration, release acceptance.

The first three are prerequisites for trustworthy multi-metric results: adding more numbers to misaligned frames or mislabeled inputs does not make the comparison more reliable.
