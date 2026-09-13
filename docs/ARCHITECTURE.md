# Standard analysis architecture

The production Standard path runs VMAF v1, XPSNR and source-aware CAMBI on the bundled native engine. The SwiftUI workflow owns stable queue/run IDs and awaits the calculator before reusing a job. `VMAFCalculator` is a compatibility bridge; `AnalysisResult` is the authoritative, immutable result and export contract.

## Boundaries and ownership

- `AnalysisAdmission`: one complete active analysis per app process across all windows/batches, with a FIFO cancellation-aware queue. A queued job allocates no input/engine resources, cancelled waiters never execute, and failure/cancellation releases the permit before another job starts. Explicit service cancellation and enclosing Task cancellation both cancel queued admission.
- `AnalysisService`: one comparison; captures file identities and configuration, probes inputs, validates correspondence, stages a safe model filename, executes metrics, validates coverage and checks end-of-run hashes.
- `OwnedProcess`: one child at a time; executable URL and arguments only, no shell/path/library fallback. Dedicated concurrent drains prevent stdout/stderr deadlock. Task cancellation or explicit cancellation sends TERM, escalates to KILL after 750 ms if necessary, awaits/reaps the process, then finishes both drains. A rejected concurrent launch cannot erase another child's ownership. Temporary logs are removed by the service's `defer` on every exit.
- `AnalysisProbe` / `AnalysisCorrespondence`: decoded video metadata, integer PTS/time bases, per-frame durations and the initial strict comparison policy.
- `MetricDecoder`: libvmaf frame/pooled/aggregate JSON and XPSNR frame/native aggregate parsing. Selected primary metrics are required; optional feature values are retained. Missing, undefined and infinite values remain distinct.
- `AnalysisProgressParser`: incremental machine `-progress pipe:1` records; unknown total remains indeterminate; `fps` is processing throughput, never video cadence. The service callback runs off the main actor. The legacy delegate callback is dispatched to the main queue and protected by the active run identity.
- `AnalysisCommandLine`: the same service compiled with `-D ANALYSIS_CLI` for reproducible conformance; absent from normal app builds.

All CPU/file/process work in the nonisolated async service runs outside the main actor. The workflow must capture selections before suspension, cancel its Task and retain it until completion, ignore callbacks from older run IDs, and derive result labels from the result snapshot. Callbacks should capture owners weakly; the legacy unconstrained delegate exists solely for compatibility and should not hold a value-type view that itself owns the calculator.

## Supported comparison policy

Standard currently requires one primary video stream, no attached artwork stream, progressive 8/10-bit 4:2:0 YUV, explicit BT.709 matrix/primaries/transfer, declared full or limited range and left or center chroma location. Both inputs must have the same coded dimensions, square pixels and zero rotation. Native CAMBI additionally restricts original source dimensions to 320–7680 × 200–4320 and encode dimensions to 180–7680 × 150–7680. An actionable refusal is preferable to inferring missing color or geometry metadata.

Full/limited representations are reconciled explicitly into limited-range BT.709 `yuv420p10le`. Chroma positions, rounding flags and every exact preprocessing filter are saved. Both metric adapters consume splits of those same normalized frames. No contrast correction, crop, resize, tone mapping, interpolation or frame repetition is used to conceal a defect. PQ/HLG and other transfers are refused before metric execution. The native player's separate supported-codec/color boundary is a UI concern; Standard is not a native-HDR quality claim.

Viewing profiles select the explicitly named 1080p 3H, phone 5H, 4K 1.5H or 4K 3H model, and persist its SHA-256. The native comparison canvas remains the input's original equal dimensions; selecting a model does not silently resize either input or establish the user's actual display/viewing distance. HFR variants are selected for measured average cadence ≥45 fps; the initial supported average cadence is 20–65 fps. The model identifier records that decision. VFR timestamps remain authoritative; this does not establish a new temporal model calibration. Nominal model ranges are descriptive, with no universal 0–100 clamp.

Both inputs must decode the same number of frames. Every presentation time and frame duration must correspond. Container quantization tolerance is at most 1.1 times the larger timestamp tick, capped at 20% of the smallest frame duration; it cannot absorb a one-frame displacement. A start-time difference larger than this tolerance is refused. After this explicit one-to-one check, nearest framesync handles residual container quantization. Both metric filters use `shortest=1:repeatlast=0:eof_action=endall:ts_sync_mode=nearest`, and both parsed metric counts must exactly equal the probed count.

The content screen compares every 16×16 luma frame with the matched frame and nearby source frames (±2), and identifies strong evidence of displacement/repetition. It catches the real same-count one-frame shift and freeze fixtures as well as count/duration defects. It is **not proof of semantic identity**, a general crop detector, or a complete detector of every edit in static/repetitive scenes. The source/encode selection must still represent the same intended content. Strong ambiguity causes refusal rather than a confident quality verdict. The limitations are included in every result's correspondence notes.

## Timing and result schema

`AnalysisResult.schemaVersion = 1` includes input URLs, full file SHA-256 and sizes/modification times; selected stream metadata; run/configuration identity; app/FFmpeg/libvmaf/model versions and executable/model hashes; transforms; metric definitions; native pooling; and each paired frame's original integer PTS/time base, per-side time, normalized reference time and frame duration. Inputs are hashed before and after the run; mutation discards the result.

Frame zero has normalized timestamp zero. Compared coverage sums evaluated frame durations. Last frame PTS, decoded compared coverage, container/source duration and processing FPS are separate concepts. A nominal one-second Matroska stream may have 0.999 seconds of decoded packet extent due to millisecond quantization; the app preserves that measured extent instead of substituting a nominal frame-rate calculation. 24/60 fps and 24000/1001/VFR mappings are covered by exact-timestamp tests. Player frame navigation must use per-side timestamps from this map.

`MetricValue` encodes finite signed values as JSON numbers, positive/negative infinity as `"+infinity"`/`"-infinity"`, undefined as null and unavailable as `"unavailable"`. Zero is always a measurement, never a missing-value substitute. Unknown optional numeric features and numeric aggregates survive parsing. Empty/truncated logs, missing selected primary outputs and incomplete counts fail. `LegacyMetricImport` preserves a legacy log but explicitly identifies model/provenance/timing as unknown; it never reconstructs a 30 fps timeline or uses current UI selections to label old results.

The bridge's old auxiliary motion/ADM/VIF fields are optional. Modern VMAF v1 need not emit legacy VIF; absent values must display/export as unavailable. The authoritative schema carries all selected metric definitions and values. Imported bridge construction validates required primary/frame fields instead of force-unwrapping them.

## Metric orientation and pooling

- VMAF: distorted first, reference second. The selected v1 model receives original encode width, height and bit depth through `cambi.*` model options. This is separate from the 10-bit comparison representation.
- XPSNR: reference first, distorted second. Store Y/U/V frame outputs and native distortion-domain plane averages from FFmpeg's final summary. The minimum plane average is a sequence aggregate, **not** a worst-frame score or arithmetic mean of frame dB. Identity infinity is valid.
- CAMBI: preserve encode, source and upstream full-reference `max(0, encode − source)` outputs. The engine's option-suffixed encode key is retained and also exposed under the canonical `cambi_encode` alias. Native means are preserved; source banding is visible even when no new banding was introduced. Default diagnostic EOTF is BT.1886; no HDR validity or perfect causal attribution is claimed. CAMBI already contributes to VMAF v1, so it is a diagnostic, not another independent vote.

The pinned native CLI and the Swift service have identical per-frame VMAF/CAMBI values on the tested 8-bit encode → 10-bit shared pipeline fixture. XPSNR asymmetric orientation also matches exactly. These are executable conformance observations, not assertions of universal perceptual accuracy.

## Explicit resource budget

Only one complete `AnalysisService.analyze` job is admitted at a time across the app process; unrelated windows queue without starting preflight or subprocesses. Current supported analysis is capped at **500,000 decoded frames per input**, **256 MB captured metadata stdout**, **512 MB combined metric log files**, and **128 KB diagnostic stderr tail**. Metric log growth is checked every 100 ms during execution and once before parsing; over-budget jobs are terminated/reaped and return an actionable error with no partial result. Stdout overflow similarly stops the child. Worker counts are clamped to 1–8 and the effective value is recorded.

Signature buffers are 256 bytes per decoded frame, with no extra byte-array copies and released before metric decoding. Metadata/logs and the immutable result are still materialized; the caps bound allocations but are not a measured fixed process-RSS guarantee. The disk watchdog can overshoot its byte threshold by up to one polling interval of engine writes. Large-result storage/retained batch counts are separately bounded by the workflow. Long-duration throughput, peak RSS and energy require their own measured acceptance evidence; short conformance fixtures do not establish those performance claims.

## Reproducing verification

```sh
swiftc -O -D ANALYSIS_CLI -o /tmp/bettervmaf-analysis-cli \
  VMAF/Analysis*.swift VMAF/OwnedProcess.swift VMAF/MetricDecoder.swift VMAF/VMAFCalculator.swift
/tmp/bettervmaf-analysis-cli VMAF/Resources/engine source.mkv encode.mkv /tmp/comparison.json
xcodebuild test -project VMAF.xcodeproj -scheme VMAF -destination 'platform=macOS' \
  -derivedDataPath /tmp/bettervmaf-core-build \
  -only-testing:VMAFTests/AnalysisCoreTests -only-testing:VMAFTests/AnalysisProcessTests CODE_SIGN_IDENTITY=-
```

The 14 analysis tests pass on the development Apple Silicon Mac. They exercise real process launch/drains, ignored-TERM escalation and PID reaping, cancellation before launch, concurrent ownership, byte-boundary progress, bounded output/logs, hashing, frame mapping, explicit color/geometry/multistream refusals, selected/optional/nonfinite metric parsing, bundled Standard identity, safe punctuation paths, same-count shifted content, malformed imported primary outputs and diagnostic reset.

`AnalysisAdmissionTests` adds five checks for whole-job serialization, cancellation while queued (including the real service wrapper and explicit cancel), and permit release after failure/cancellation. These pass in a standalone Swift test executable without launching the app.

[Actual service corpus evidence](evidence/analysis-service-corpus.json) records 58 source/encode cases: 42 accepted and 16 refused, with no policy mismatches. It also records actual lossless remux and VFR checks, same-count shift regression and independent native CLI parity. The [corpus workflow](CORPUS.md) records fixture origins and generation. One instructive identity case is the dark gradient: VMAF 94.909757 while XPSNR is infinite and source/encode CAMBI are equal with full-reference CAMBI zero; identity is not hardcoded to VMAF 100.

Upstream contracts: [VMAF v1 models](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md), [CAMBI](https://github.com/Netflix/vmaf/blob/master/resource/doc/cambi.md), [FFmpeg XPSNR](https://ffmpeg.org/ffmpeg-filters.html#xpsnr-1). Exact shipped revisions, capabilities and notices live with `Resources/engine/manifest.json` and the native engine build documentation.
