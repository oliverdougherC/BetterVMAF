# Apple Silicon performance evidence

Measured 2026-09-13 UTC on **Apple M4 Pro, 24 GiB unified memory, macOS 27.0 (26A428), Xcode 26.6 (17F113)**. This was an active developer Mac on battery, with other applications and development work running. These are reproducible engineering observations, not isolated architecture speedups, battery-life measurements, or universal responsiveness guarantees.

Eight 2-second synthetic testsrc2 clips cover 1080p/4K × 8/10-bit × 24/60fps. Eight-bit inputs use H264; ten-bit inputs use HEVC. The same file supplies source and encode to isolate pipeline cost. These are throughput fixtures, not a replacement for adversarial or real-media conformance sources.

## Engine before and after

The baseline runs the previous x86_64 FFmpeg 8.0.1-tessus helper under Rosetta with the checked-in VMAF 0.6.1 1080p model, 99 metric threads and automatic decoder threading. That same legacy model is deliberately fixed across both helpers and every resolution for the comparison; this is not the old app’s automatic 4K-profile selection or a complete app launch-to-result baseline. The current helper runs native arm64 FFmpeg n8.1 with four metric and four decoder threads in this benchmark. The external fixture generator is Homebrew FFmpeg 9.0; it is not the bundled runtime. This comparison captures the **combined architecture, engine-version and threading-policy change**. Engine/model SHA256s, input hashes and exact argument arrays are retained in the raw evidence.

| Input | Decode-only fps, baseline/current | VMAF 0.6.1 pipeline fps, baseline/current | Peak pipeline RSS MiB, baseline/current |
|---|---:|---:|---:|
| 1080p-8bit-24fps | 682.1 / 1458.3 | 60.6 / 126.8 | 1278 / 388 |
| 1080p-8bit-60fps | 1486.5 / 2143.2 | 66.6 / 128.0 | 2013 / 388 |
| 1080p-10bit-24fps | 495.2 / 449.7 | 48.5 / 80.3 | 2175 / 574 |
| 1080p-10bit-60fps | 910.8 / 729.6 | 53.3 / 94.2 | 2690 / 578 |
| 2160p-8bit-24fps | 317.5 / 485.2 | 14.2 / 33.4 | 5954 / 1467 |
| 2160p-8bit-60fps | 617.9 / 627.2 | 13.1 / 34.4 | 5999 / 1479 |
| 2160p-10bit-24fps | 164.1 / 147.7 | 9.8 / 22.8 | 5057 / 2235 |
| 2160p-10bit-60fps | 237.2 / 189.7 | 10.0 / 23.9 | 5384 / 2257 |

The Standard graph matches the integrated shared limited-range BT709 ten-bit normalization, explicit chroma siting, AVTB timestamps and EOF policy. It selects VMAF v1.0.16 3H at 24fps and the corresponding HFR model at 60fps, with original encode geometry/bit-depth CAMBI parameters, separate full-reference CAMBI, and XPSNR in reference/distorted order. It measures the metric process; app hashing, probes, content signatures and UI publication are excluded. The decode-free pass reads predecoded rawvideo: it removes codec decoding but still includes cached disk reads, filters, startup, and result flush.

| Input | Decode-only fps | Decode-free Standard fps | Full Standard fps | Result-ready seconds | Peak RSS MiB | Mean child CPU % |
|---|---:|---:|---:|---:|---:|---:|
| 1080p-8bit-24fps | 1337.1 | 51.8 | 51.2 | 0.937 | 628 | 415 |
| 1080p-8bit-60fps | 2090.5 | 52.0 | 52.7 | 2.278 | 626 | 426 |
| 1080p-10bit-24fps | 453.1 | 55.0 | 49.5 | 0.969 | 676 | 439 |
| 1080p-10bit-60fps | 696.2 | 55.5 | 54.0 | 2.224 | 677 | 448 |
| 2160p-8bit-24fps | 475.9 | 12.7 | 12.7 | 3.783 | 2397 | 423 |
| 2160p-8bit-60fps | 610.1 | 10.1 | 12.0 | 9.962 | 2396 | 429 |
| 2160p-10bit-24fps | 142.6 | 12.8 | 12.1 | 3.979 | 2614 | 450 |
| 2160p-10bit-60fps | 187.8 | 12.3 | 12.6 | 9.524 | 2682 | 462 |

A one-second looping decode workload exited 73.9 ms after SIGTERM in the baseline and 48.1 ms in the native run. This is child-exit latency, not application cancellation acknowledgment or stale-result suppression.

Result-ready means engine completion with JSON flushed, **not first app result**. First positive machine progress is recorded separately; it does not prove a metric already exists. Throughput is frames/wall time. The libvmaf JSON `fps` field is processing throughput, never source cadence. Child CPU percent is user+system CPU seconds/wall time; 100% means one core. RSS is Darwin `wait4` per-child peak bytes, excluding application/GPU memory.

All eight native software/VideoToolbox paths produced identical per-frame decoded hashes in the AVC/HEVC fixture matrix. **Keep software decoding as the default**: this does not establish parity for AV1, HDR, other codec profiles, rotation, or all real files. Both command arrays and every decoded hash are retained.

`powermetrics --samplers cpu_power,gpu_power -n 1 -i 1000` was attempted and refused because superuser access is required. The observed battery snapshot was 53%, discharging. No GPU utilization, joules, energy-impact score, or battery-life result is inferred from CPU/RSS or that snapshot.

## Large timelines

The baseline source creates 12 marks/frame in the line chart and 11/frame in the heatmap, including 10 redundant grid rules/frame in each. At 216k points these are 2.592 million and 2.376 million marks; at 1 million points, 12 million and 11 million. These exact source-level counts exclude axes and the zoom minimap; they are not measured renderer allocations.

The old per-point full-array min/max and linear hover were measured in an optimized Foundation microbenchmark. Full quadratic heatmap rendering at those sizes was not performed; extrapolated timings in the raw record are estimates, not observed UI stalls. The current benchmark compiles the application's actual `TimelineData.swift`, retains adjacent opposing spikes (-17 and 111), prepares 500 buckets 31 times, and performs 100,000 binary-search lookups.

| Raw points | Plotted points | Preparation median/p95 ms | Nearest lookup mean µs | Peak process RSS MiB |
|---|---:|---:|---:|---:|
| 216,000 | 1002 | 0.921 / 1.073 | 0.057 | 12.4 |
| 1,000,000 | 1002 | 2.869 / 3.414 | 0.049 | 43.0 |

The chart contract is at most `2*buckets+2` points. Raw data remains available to summaries and exports; the benchmark asserts both extrema survive. RSS is cumulative process peak, not total SwiftUI memory. These are main-thread algorithm microbenchmarks, **not display frame-pacing measurements**.

## Budgets and acceptance limits

The benchmark explicitly uses four metric and decoder threads. The application currently defaults to half the active core count, capped at eight (seven on this 14-core Mac); its configuration is therefore distinct from the four-thread benchmark. The implementation bounds these worker settings and chart output. Metadata/frame probing uses two decoder threads. A shared admission queue permits one complete analysis across all app windows; waiting jobs allocate no engine resources. Do not present four as the app default. A **3 GiB helper RSS** threshold is useful for regression review of this exact four-thread 4K ten-bit Standard matrix; observed peaks are below it. It is not an enforced limit or a validated threshold for the app’s seven-thread default. It is not a guarantee for arbitrary codecs or native-player buffers. Do not increase comparison concurrency solely because unified memory appears free.

Candidate integrated acceptance targets are no main-thread task above 16.7 ms during 60 Hz interaction, p95 interaction response below 100 ms, and owned-process cancellation completion below one second. The latter was selected after observing the metric workload and the implemented 750 ms termination grace; a speculative 250 ms target would not describe this implementation. **UI targets have not passed simply because this benchmark passed.** Actual app first-result latency, frame pacing/input response while analysis and large export run, and long-clip playback alignment require the integrated native UI pass. Do not close PLA-540 with a launch-only test or these algorithm timings as a substitute.

## Reproduce

```sh
python3 scripts/performance/benchmark_engine.py --engine /path/to/legacy/ffmpeg --threads 99 --decode-threads 0 --label baseline-legacy --output /tmp/baseline.json
python3 scripts/performance/benchmark_engine.py --engine VMAF/Resources/engine/ffmpeg --threads 4 --label native-legacy --parity --output /tmp/native-legacy.json
python3 scripts/performance/benchmark_engine.py --engine VMAF/Resources/engine/ffmpeg --threads 4 --label native-standard --standard --metric-only --model VMAF/Resources/engine/models/vmaf_v1.0.16_3d0h.json --output /tmp/native-standard.json
swiftc -O scripts/performance/chart_baseline.swift -o /tmp/chart-baseline
/tmp/chart-baseline
swiftc -O VMAF/TimelineData.swift scripts/performance/chart_current.swift -o /tmp/chart-current
/tmp/chart-current
```

Generated media stays outside Git in `/tmp/bettervmaf-performance/matrix`. Temporary rawvideo is removed after its measurement; allow several GiB of disk space. The generator is explicitly external Homebrew FFmpeg and is never substituted for the app's pinned helper. Generation command arrays and hashes make the inputs auditable; encoder build differences may change compressed hashes. The synthetic matrix has known numeric test-pattern inputs; the Standard benchmark explicitly applies its documented BT709 normalization rather than relying on encoder metadata. The separate UI workload includes verified in-band BT709 metadata. The baseline helper is preserved externally at `/tmp/bettervmaf-performance/ffmpeg-legacy` for this session.

Raw records: [baseline engine](evidence/performance-baseline-engine.json), [native with same legacy model and decode parity](evidence/performance-native-legacy-model.json), [native Standard and decode-free pass](evidence/performance-native-standard.json), [old algorithm/mark counts](evidence/performance-baseline-chart.json), [actual current timeline algorithm](evidence/performance-current-chart.json). The [alternative walkthrough](ALTERNATIVE_COMPARISON.md) records the separate fixed-task experiment.

## Coordinated native UI capture

`python3 scripts/performance/generate_ui_workload.py` creates the four-second, 240-frame 4K60 source/encode pair outside Git. The [workload record](evidence/performance-ui-workload.json) includes hashes, generation/VUI-tagging commands and verified native-ffprobe fields. Coordinate an actual analysis/export/seek workload before starting:

```sh
python3 scripts/performance/record_ui_trace.py --pid APP_PID --seconds 45 --name analysis-export
```

The recorder uses the installed Xcode Animation Hitches template and records failures honestly. It does not drive the UI or manufacture workload. Trace bundles stay outside Git; retain compact exported tables and summaries with the exact interaction intervals. An idle or failed capture is not evidence of responsiveness.

### Actual app workload and Instruments limitation

The integrated Debug app (PID 88556) ran the tagged four-second 4K60 pair with the app’s seven-thread setting. The parent operator completed all 240 evaluated frames with HFR VMAF 78.360249 and XPSNR minimum native plane average 38.071 dB, then interacted with playback and the export sheet. The later native export attempt exposed a sandbox destination issue, separate from the profiler failure. The export owner repaired it and completed native PDF/JSON saves on the review fixture; saved artifacts, hashes and the final fixed-task outcome are recorded in the alternative study. The earlier process sample is not retroactively evidence for the repaired export path.

[App/process samples](evidence/performance-ui-process-samples.json) cover 02:28:57.929–02:29:47.248 UTC at about 1Hz. Observed app RSS peaked at 227.4 MiB with 47.7% recent CPU. Only one nonzero late-analysis helper sample was captured: 3474.7 MiB and 737.8% recent CPU. These are sampled observations, **not lifetime peaks**, and the short overlap cannot establish steady-state memory or frame pacing.

The attempted 60-second Xcode Animation Hitches capture printed the time-limit/stopping messages but stalled during finalization for nearly four minutes. SIGINT did not complete; SIGTERM stopped only the recorder. The partial trace contained a 40KB issue store and no complete template; TOC export returned **Document Missing Template Error**. A stack sample showed a DTXConnectionServices semaphore wait; the exact cause is unestablished. This is a concrete external Instruments recording/finalization blocker on the installed OS/toolchain, not evidence of an application hitch. [Attempt and diagnosis](evidence/performance-ui-analysis-export.json). No usable frame-pacing, hitch count or input-response distribution was obtained. The recorder now bounds startup/finalization time and preserves failure details.

### Same-workload worker-count decision

Four paired ABAB metric-process trials compared four and seven workers on the exact tagged 4K60 UI source/encode files, the same HFR model and shared normalization. All trials retained 240 frames and the identical native VMAF mean 78.360249. These active-Mac observations do not isolate thermal/background variability, but the resource/throughput tradeoff was substantial in both pairs.

| Trial | Workers | Pipeline fps | Peak child RSS MiB | Wall seconds | Mean child CPU % |
|---|---:|---:|---:|---:|---:|
| 1 | 4 | 13.82 | 2453 | 17.371 | 436 |
| 2 | 7 | 19.98 | 3958 | 12.010 | 744 |
| 3 | 4 | 11.83 | 2477 | 20.287 | 420 |
| 4 | 7 | 19.28 | 3933 | 12.449 | 748 |

Across these two repeats, four workers used about 38% less peak RSS but delivered about 35% lower throughput. **Retain the existing seven-worker default on this 24 GiB Mac and the eight-worker cap.** This evidence does not support claiming a four-worker default would preserve speed. No unmeasured policy was added for smaller-memory Macs. The 3 GiB figure above remains a four-worker benchmark-review threshold, not an app-wide enforced budget.

One-second active metric-process cancellation probes exited after 1658.9 ms (4 workers) and 1310.2 ms (7 workers) following SIGTERM. These probe child termination, not the app’s UI cancellation path.

[Exact paired commands, hashes, CPU/RSS, parity and cancellation evidence](evidence/performance-worker-counts.json). Reproduce with `python3 scripts/performance/compare_worker_counts.py` after generating the UI workload.

The actual application `OwnedProcess.swift` was then compiled into a standalone cancellation harness with the exact metric arguments. Cancellation returned only after child exit and both pipe drains, raising `CancellationError`, in **813.5 ms (four workers)** and **835.5 ms (seven workers)**. The owner’s 750 ms grace period and kill escalation bound the slower graceful metric exit. These are one real owner-path trial per worker count and remain distinct from a UI click-to-response measurement. [Owner-path evidence](evidence/performance-owned-cancellation.json).

```sh
swiftc -O VMAF/AnalysisResult.swift VMAF/OwnedProcess.swift scripts/performance/owned_cancellation.swift -o /tmp/owned-cancellation
/tmp/owned-cancellation docs/evidence/performance-worker-counts.json
```

### Native playback and scheduling under concurrent work

The final native XCTest regression generated a 12-second 640×360/60fps H.264 movie with720 frames, verified B-frames and keyframes at0,237,474,711. Both AVPlayerItemVideoOutput instances returned exact requested PTS at frame0,1,239,240,359,478 and719. Twelve live output samples remained matched while the real Standard service ran and a full JSON export serialized off the main actor. [Native GOP evidence](evidence/native-gop-playback.json).

The same run recorded617 main-actor heartbeat samples with p95 gap11.081ms and maximum11.162ms for a nominal10ms sleeper. This is an observed scheduling/interaction seam, not compositor presentation timestamps, a human click-latency distribution, or proof of sustained60fps display. It narrows the remaining profiling gap without relabeling the failed Instruments capture as successful.
