# Integration execution

Base: `78f6631605132d0ea75cf92869e65231968d46fb`; branch `codex/bettervmaf-next`.
Authoritative issue snapshot: [live requirements](LINEAR_REQUIREMENTS.md). This is an implementation sequence, not completion evidence.

1. Extract owned processes and immutable analysis contracts with regression tests; build the pinned native engine independently.
2. Validate timestamps, correspondence, geometry and SDR color before enabling VMAF v1, XPSNR and source-aware CAMBI.
3. Integrate bounded plots, distributions and exact review intervals with synchronized playback; restore safe single/batch workflows and reproducible exports.
4. Execute adversarial corpus, optional deeper/HDR/sampling experiments, and Mac resource measurements.
5. Review combined changes, native tests and actual UI; package and validate the final app; reconcile docs/Linear and open one integration PR without merging.

## Bounded visualization cleanup

Scope: `VMAFGraphView.swift`, `HeatMapView.swift`, new shared `TimelineData.swift` / `MetricTimelineView.swift`, and their tests.

First test exact time lookup, min/max envelope spike retention, bounded marks, and empty/constant/single-point domains. Then remove repeated scans, duplicate grids, per-point timers and the duplicated graph implementation. Preserve raw metric arrays; prepare viewport data off the main actor. Use numeric metric axes without uncalibrated Poor/Excellent labels. Test the shared renderer's algorithms before switching the existing views; inspect actual Mac UI after integration.

## Ownership

- Analysis service/schema/tests: analysis_core.
- Native engine/resources/provenance: native_engine.
- Single/batch/playback/export: comparison_ui.
- Corpus/optional experiments: corpus_research.
- Performance evidence and alternative comparison: performance_validation.
- Timelines, distributions/concerns, integration, packaging, final validation and Linear: root.

All agents share the isolated worktree with bounded write ownership. Existing dirty beta checkout and archive/release refs remain preserved.
