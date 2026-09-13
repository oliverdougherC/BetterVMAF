# Integration validation and issue map

Integration PR: [#3](https://github.com/oliverdougherC/BetterVMAF/pull/3), branch `codex/bettervmaf-next`, based on main `78f6631605132d0ea75cf92869e65231968d46fb`. Implementation is unmerged. This record distinguishes completed checks from remaining acceptance; a source change alone is not proof of completion.

## Native evidence collected

- Apple M4 Pro, 14 CPU cores, 24 GiB, macOS27.0 (26A428), Xcode26.6. macOS15 CI is a separate environment and does not establish every15.2/hardware combination.
- Native engine:22/22 upstream libvmaf tests; all eight v1 models; exact independent VMAF/CAMBI per-frame CLI parity; asymmetric XPSNR orientation; source-aware banding; hashes reproduced by a second recipe build. [Engine evidence](ENGINE.md).
- Actual Swift analysis service:58 corpus cases,42 accepted/16 expected refusals, no policy mismatches; same-count displacement refused; VFR and unchanged MP4→MKV timestamp quantization accepted. [Service record](evidence/analysis-service-corpus.json).
- 14 focused core tests initially passed, including actual kill/reap and both-pipe drains, concurrency ownership, parser boundaries, metadata/time/geometry/refusals, source changes and output budgets.
- Sixteen focused native workflow/export/playback tests passed and exercise stable IDs, cancellation/retry/reference changes, real schema pooling, selected fields/nonfinite roundtrip, atomic create/overwrite, and displayed AVPlayer output PTS.
- Live CUA inspection of the real app found a preceding-frame seek bug and a sandbox save-grant bug; both were fixed. Frame23 is visually confirmed on both burn-ins at0.958333s; concern1.000–1.500 selects frame24 and the black encode interval. Source changes immediately clear stale results. A240-frame4K60 run completed with VMAF78.360 and XPSNR minimum native plane38.071dB. [Interactive record](evidence/native-interactive.json).
- A720-frame/12-second60fps H.264/B-frame GOP regression verified exact random seeks and twelve live paired outputs during real analysis and JSON export. Main-actor scheduling observations are qualified separately from compositor pacing in [PERFORMANCE.md](PERFORMANCE.md).
- Mounted Debug package checks passed, including ad-hoc signatures, native metric execution with system-only runtime paths, resources, notices and corresponding source archive. Final Release status is recorded below.
- [Mac performance](PERFORMANCE.md) contains separate decode, metric, chart and process observations. Four-worker microbenchmarks must not be confused with this Mac's seven-worker app default. The native owner completed cancellation in roughly0.81–0.84s under active metric load. No unmeasured battery or60fps UI guarantee is made.

## Issue mapping

All implementation rows refer to the same integration PR. They await review rather than being marked Done before merge.

| Issue | Implementation / evidence | Acceptance boundary |
|---|---|---|
| PLA-520 | AnalysisCoreTests, AnalysisProcessTests, Workflow/Export/Timeline/ReviewSummary tests | Native suite, actual process and bundled engine replace template-only coverage |
| PLA-521 | OwnedProcess, VMAFCalculator, ComparisonSession | TERM→KILL, reap/drain, run IDs; cancel/clear/retry and rejected concurrent ownership |
| PLA-522 | AnalysisFileIdentity, AnalysisResult, ComparisonSession, immutable exports | Full hashes before/after analysis; stale selections cleared; batch pins source identity |
| PLA-523 | OwnedProcess, AnalysisProgressParser, controlled job directory | Argument arrays, split-byte progress, typed diagnostics, bounded logs and teardown |
| PLA-524 | AnalysisProbe/AnalysisFramePair, rational PlaybackController | Original PTS/timebases and durations;24/60/24000÷1001/VFR; no30fps inference |
| PLA-525 | AnalysisCorrespondence, actual-service corpus | Explicit EOF/nearest within bounded timestamp quantization; conservative displacement screen |
| PLA-526 | Shared AnalysisService.normalization | Tagged BT.709 full/limited8/10bit; original metadata retained; unsupported HDR/geometry refused |
| PLA-527 | AnalysisResult/MetricValue/MetricDecoder | Versioned selected metrics; null/infinity/signed values; legacy import stays unknown |
| PLA-528 | scripts/engine, resources/engine, ENGINE.md | Pinned arm64 self-contained helpers, models, notices, source/build provenance and execution |
| PLA-529 | TimelineData and shared MetricTimelineView | Bounded extrema envelope, finite gaps, binary search, raw data preserved;216k/1M checks |
| PLA-530 | Numeric metric timelines and progressive details | No clip-relative Poor/Excellent categories, transparency claims or universal clamp |
| PLA-531 | CORPUS.md and source/generation/evidence manifests |16 scenes/57 artifacts;41 native pairs plus58 service policy cases; no human-calibration claim |
| PLA-532 | Eight pinned VMAFv1 models, explicit viewing profiles/HFR | Executed actual FFmpeg/library/model tuple; no silent scale/profile substitution |
| PLA-533 | Shared XPSNR adapter/decoder | Reference-first orientation, Y/U/V/native pooling/min-plane aggregate and infinity |
| PLA-534 | CAMBI encode/source/full-reference outputs | Original dimensions/bitdepth retained; diagnostic context, not independent vote |
| PLA-535 | EXPERIMENTS.md, native SSIMULACRA2 helper/conformance | Experiment executed; production Deep remains deferred on stated gates |
| PLA-536 | ReviewSummary and deterministic fixtures | Duration-weighted tails/median/mean, isolated/sustained intervals, reasons and disagreement |
| PLA-537 | PlaybackController/PlaybackComparisonView, native displayed-PTS tests and CUA | Rational seek/step, shared transport/wipe/zoom/pan/loop; native-codec boundary explicit |
| PLA-538 | Concise setup/results, native controls, exact concern navigation | Inputs collapse after result; Framewise/video-compare comparison recorded fairly |
| PLA-539 | ExportManager/ExportOptionsView/PDFGenerator | Background serialization, practical PDF, selected options, immutable provenance, sandbox-safe atomic save |
| PLA-540 | PERFORMANCE.md, native matrix/AB trials/resource sampler | Code budgets and measured observations; compositor pacing/energy limitations below |
| PLA-541 | BatchComparisonSession/ComparisonTradeoffs | Immutable source/config, actual retention cap, compatible native profiles, retry/inspection; in-session queue |
| PLA-542 | create_dmg.sh and scripts/package | Native mounted package proof; final Release and environment limitations below |
| PLA-543 | EXPERIMENTS.md,12 PQ/HLG CPU/MPS cases | Display assumptions/runtime/RSS/package cost measured; native-HDR product deferred |
| PLA-544 | EXPERIMENTS.md, actual context-window/full comparisons | Deterministic coverage and discovered missed defects; Quick product deferred |

## Deliberate supported boundaries and remaining validation

- Standard accepts one unambiguous, progressive, square-pixel, unrotated, equal-dimension BT.709 SDR pair. Scaling/rotation/crop normalization and unknown color assumptions are not silently applied. Strong nearby displacement is refused, but16×16 luma screening cannot prove every semantic edit or crop; verify the same source/edit and inspect video.
- 500,000 decoded frames per analysis,512MiB combined metric-log budget,256MiB captured process stdout,128KiB diagnostic tail; at most eight batch candidates and one million retained samples. These are enforced support bounds, not a claim that maximum-size runs have been profiled on every Mac. Results/metadata are materialized within those limits.
- Native playback support is narrower than FFmpeg decoding. Unsupported native codecs retain results with an explanation and require a supported lossless intermediate plus reanalysis for visual inspection.
- SSIMULACRA2, HDR/temporal product integration and sampled Quick mode are disabled after measured experiments. Read [EXPERIMENTS.md](EXPERIMENTS.md) for actual failed/unpassed gates and required work. No weighted quality score or sampled global-worst claim exists.
- Instruments failed to finalize a trace (`Document Missing Template Error`); the partial trace is not pacing evidence. `powermetrics` requires elevated access, so energy/battery claims are excluded. Process sampling, native playback tests and actual interactions establish narrower facts. Required compositor/energy profiling remains an external validation limitation.
- Local packages are ad-hoc signed, not Developer ID signed/notarized. A separate pristine physical Mac and exact macOS15.2 execution have not been observed locally. macOS CI and system-only packaged execution are documented independently.

## Final combined verification

Final suite, CI, Release package and exact-commit evidence are being collected. PR remains draft until the final pass and any acceptance gaps are reconciled. See the PR and Linear for current review state; do not infer completion from this interim paragraph.
