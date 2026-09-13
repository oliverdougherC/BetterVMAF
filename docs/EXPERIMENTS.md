# Optional metric and coverage experiments

PLA-535, PLA-543 and PLA-544 were executed on an **Apple M4 Pro, 14-core CPU, 24 GB unified memory, macOS 27.0 (26A428)**. Standard SDR remains the shipped analysis path. The decisions below separate demonstrated reference behavior from production integration gates. No optional metric or quick scan is silently substituted into Standard.

## Reproduce

Use an external Python 3.11 virtual environment and `scripts/experiments/requirements-lock.txt`. It pins the measured ColorVideoVDP revision and Python packages. Native libjxl research builds need CMake, pkg-config, jpeg-xl, highway, little-cms2, brotli, OpenEXR and libpng from Homebrew plus Xcode's SDK; they are not standalone app distribution artifacts.

```bash
python3.11 -m venv ../BetterVMAF-corpus/venv
../BetterVMAF-corpus/venv/bin/pip install -r scripts/experiments/requirements-lock.txt
scripts/experiments/build_ssimulacra2.sh ../BetterVMAF-corpus
../BetterVMAF-corpus/venv/bin/python scripts/experiments/ssimulacra2.py --root ../BetterVMAF-corpus
../BetterVMAF-corpus/venv/bin/python scripts/experiments/ssimulacra2_conformance.py --root ../BetterVMAF-corpus
../BetterVMAF-corpus/venv/bin/python scripts/experiments/colorvideovdp.py --root ../BetterVMAF-corpus --device mps
../BetterVMAF-corpus/venv/bin/python scripts/experiments/colorvideovdp.py --root ../BetterVMAF-corpus --device cpu
../BetterVMAF-corpus/venv/bin/python scripts/experiments/colorvideovdp.py --root ../BetterVMAF-corpus --width 1920 --frames 12 --cases identity,periodic_flicker
python3 scripts/experiments/quick_scan.py --root ../BetterVMAF-corpus --engine VMAF/Resources/engine
```

Times are actual observations on a shared development machine, including startup where recorded. They are not isolated battery/performance guarantees. `/usr/bin/time -l` RSS is in bytes on this Mac. `powermetrics --samplers cpu_power -n 1 -i 100` returned “must be invoked as the superuser”; CPU time and MPS allocations were recorded, but **joules/battery drain were not measurable without elevated access**.

## SSIMULACRA2: native conformance passed; Deep integration deferred

Pinned upstream: **libjxl 0.12.0**, revision `a7a9c787341cf703dede03c2009fa460cae5e5df`, SSIMULACRA2 v2.1, BSD-3-Clause. Sources: [author metric definition](https://github.com/cloudinary/ssimulacra2), [pinned reference](https://github.com/libjxl/libjxl/blob/a7a9c787341cf703dede03c2009fa460cae5e5df/tools/ssimulacra2.cc), [license](https://github.com/libjxl/libjxl/blob/a7a9c787341cf703dede03c2009fa460cae5e5df/LICENSE).

The experiment builds an arm64 `ssimulacra2_linear` adapter around the unmodified upstream computation. It accepts exactly one pair of bounded, finite, normalized, interleaved float32 linear-sRGB frames; it rejects wrong dimensions, truncated/trailing data and out-of-contract values. It allocates a row of input data and two image bundles rather than buffering a whole video. This is an experiment helper, not an app backend.

[Native conformance evidence](evidence/experiment-ssimulacra2-conformance.json) compares its outputs with the independently invoked source-built reference executable reading float32 EXR at 640×360,1920×1080 and 3840×2160. Differences were **0.0** at printed precision, satisfying 1e-6 tolerance. Severe color inversion scored **−173.27645098**, identity 100, truncated input failed, and a running 4K process was terminated and awaited in milliseconds. Full signed values remain in the evidence.

Color findings matter more than an API wrapper:

- Upstream converts to linear sRGB. PFM/PPM without hints default to **encoded sRGB**, not linear RGB; passing linear PFM directly would apply the transfer twice. EXR is explicitly linear. [Pinned PNM decoding](https://github.com/libjxl/libjxl/blob/a7a9c787341cf703dede03c2009fa460cae5e5df/lib/extras/dec/pnm.cc).
- A 10-bit limited neutral ramp was decoded via FFmpeg/zscale to float32 linear sRGB and checked against the declared **display-referred BT.1886 gamma 2.4** contract. Maximum absolute gray error was about 3.6e-5, below 1e-4 tolerance for approximate float conversion. The initial inverse BT.709 camera-OETF expectation differed by 0.07247; that is a different scene-referred contract, not a tolerance to waive. The [upstream zimg dispatch](https://github.com/sekrit-twc/zimg/blob/master/src/zimg/colorspace/gamma.cpp) explicitly chooses between these interpretations.
- [High-precision representation tests](evidence/experiment-ssimulacra2-reference.json) also compare 16-bit linear PNG, float EXR and encoded-sRGB float PFM. Tiny quantization/transform differences are observable; equivalent representations do not automatically score 100. Changing transfer metadata with unchanged numeric codes produced **−44.66557518**. No screenshot or 8-bit roundtrip feeds an analysis score.

The raw adapter measured roughly 0.21 s at 1080p and 0.97 s at 4K in the final recorded pass, with about 395 MB / 1.53 GB peak RSS. Reference-process timings varied substantially under concurrent development load. Cancellation proves child teardown for this helper; it does not prove an app frame queue is bounded.

**Decision: defer Deep UI/backend.** Native metric conformance and a neutral-ramp conversion are demonstrated. Full color/gamut/chroma-location conformance against the app's shared decode path, a production buffer/backpressure contract, standalone dependency packaging, and energy evidence are not. The shipped Standard engine supplies 10-bit YUV and does not include the experimental managed linear-sRGB path. Adding a private 8-bit or ad-hoc conversion to get a score would violate the shared contract. Remaining work is to qualify that path on color fixtures, package the helper without Homebrew linkage, enforce per-job memory limits, and benchmark alongside the viewer. This is a measured feasibility result and an explicit unpassed integration gate, not a claim that the optional app feature is implemented.

## ColorVideoVDP: HDR/temporal reference feasible; product integration deferred

Pinned **ColorVideoVDP 0.5.7**, revision `2a268bce8d56e2f3abde46df3927d8a633707a24`, MIT, with PyTorch 2.14.0 and MPS available. [Upstream code and instructions](https://github.com/gfxdisp/ColorVideoVDP/tree/2a268bce8d56e2f3abde46df3927d8a633707a24), [license](https://github.com/gfxdisp/ColorVideoVDP/blob/2a268bce8d56e2f3abde46df3927d8a633707a24/LICENSE).

The reference implementation was run on float32 **BT.2020 PQ and HLG** moving ramps with exact paired frames: identity, chroma change, one-frame flicker, periodic flicker, sustained brightness change and freeze.24 frames at 24 fps retain temporal cadence. PQ is constructed from absolute values up to 1000 cd/m²; HLG uses the BT.2100 scene OETF and upstream display OOTF. These are photometric synthetic HDR cases, unlike the metadata-refusal files in the corpus.

Both use upstream `standard_hdr_pq` / `standard_hdr_hlg`:30-inch 3840×2160 display at 0.7472 m, 1500 cd/m² peak, 1,000,000:1 contrast, 10 lux ambient. Scores characterize those stated assumptions, not the actual Mac display or a silently tone-mapped SDR rendering.

[CPU evidence](evidence/experiment-colorvideovdp-cpu.json), [MPS evidence](evidence/experiment-colorvideovdp-mps.json), and [1080p evidence](evidence/experiment-colorvideovdp-hd.json) retain input hashes, exact scores and resources. Identity was 10 JOD. CPU/MPS differed by at most **0.00011063 JOD** across 12 cases, consistent with floating-point device differences; no broad cross-device guarantee is inferred. Both detected the injected temporal and chromatic damage; severe examples produced signed negative JOD values.

For 12-frame 1080p arrays, observed MPS throughput was 2.9–8.8 fps across the PQ/HLG runs (PQ was slower; first runs include startup effects), peak process RSS reached **3.66GB**, and MPS driver allocation was about 1.09 GB. This includes the experiment's retained reference/test arrays and allocations, not an optimized streaming implementation. The measured Python environment occupies **959,772,595 bytes**, with torch 578,631,058 bytes, torchvision 9,173,827 bytes and pycvvdp 1,784,660 bytes. Those are unpacked installed bytes, not a proposed compressed app installer size. Energy was unavailable as described above.

Current Netflix upstream model guidance/release inventory was rechecked during this task; published v1 guidance specifies SDR10-bit models and no validated native-HDR model was selected. [Official model guidance](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md), [release inventory](https://github.com/Netflix/vmaf/releases).

**Decision: defer native-HDR scoring.** Reference feasibility, explicit display handling and temporal response are established. Shipping this environment would add substantial package and memory cost without a qualified streamed video decoder, packaging/offline dependency proof, real HDR camera corpus, or energy/UI coexistence evidence. Keep the app's actionable HDR refusal. Future work must preserve mastering/display metadata, qualify high-precision movie ingestion and bound temporal buffers; the observed cost must not be mislabeled as optimized native-app performance.

## Quick scan: deterministic context works on the probe; brief/periodic coverage fails

[Sampling evidence](evidence/experiment-quick-scan.json) uses real full VMAF v1 outputs for48 frames at 24 fps. It compares stride 12, seed 544 stratification (one center per 12-frame stratum), and known scene-boundary centers against all-frame analysis. Exact scored centers, coverage, proposed/actually executed context windows, expanded frames, sampled distributions and defect intersections are retained.

Contiguous windows include ±2 neighbors, merge overlaps, preserve original 24 fps cadence, and report only selected centers. Each selected window output was compared with its full-sequence counterpart: maximum center-score difference **0.0** on these fixtures. This does not establish HFR smoothing or VFR boundary equivalence. Full raw scores remain unchanged.

All three partial selectors missed the single-frame defect and all four periodic defects at their **reported centers**. They found a sustained interval because it intersected their centers. Some defect frames occur in decoded temporal context; that does not make them part of the declared sampled distribution. Expansion around an initially low center cannot discover a defect with no initial selected signal. Window subprocess overhead took roughly 0.15–0.22 s, similar to or slower than these very short full comparisons; no speedup claim is made.

**Decision: defer Quick UI.** These experiments establish a reproducible failure mode and a working same-cadence context probe, not representative discovery guarantees. Full Standard remains the default and sole coverage choice. A future scan must justify sampling on longer representative scenes, account for evaluated context when reporting coverage, qualify HFR/VFR windows, and expose partial results without a global-worst-frame or fabricated confidence claim.
