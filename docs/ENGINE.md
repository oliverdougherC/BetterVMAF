# Native analysis engine

The shipped replacement is an arm64-only engine built from source on this Mac. `VMAF/Resources/engine/manifest.json` is its immutable component/artifact inventory. It contains FFmpeg 8.1 (`9047fa1b084f76b1b4d065af2d743df1b40dfb56`), libvmaf commit `f85a853692a8c730d0270cd733c8bb30b5b93b7c`, and dav1d 1.5.3 (`b546257f770768b2c88258c533da38b91a06f737`) for software AV1 decoding. No upstream source modifications were made. The compiler deployment target is macOS 15.2. Intel is not a supported artifact; Rosetta is unnecessary.

The helpers statically include their third-party libraries and dynamically load only macOS system frameworks/libraries. They do not load Homebrew libraries. The build uses `--disable-autodetect` to prevent incidental developer-machine libraries from becoming hidden dependencies. Network protocols are disabled because analysis is local. VideoToolbox remains available for separately validated decode paths; software decoding is the default correctness baseline. GPL/nonfree options are disabled; FFmpeg identifies the actual configuration as LGPL 2.1 or later. `gblur` is available; the GPL `boxblur` filter is intentionally absent.

## Rebuild and verify

Prerequisites are arm64 macOS, Xcode command-line tools, Git, Python 3 and pkg-config. Build-only Python tools are installed in a private virtual environment: Meson 1.10.1 and Ninja 1.13.0. Sources and objects stay under `~/Library/Caches/BetterVMAF-engine`, outside Git. A clean alternate `--cache` makes a separate rebuild.

```sh
python3 scripts/engine/build.py
python3 scripts/engine/verify.py --report docs/evidence/engine-native-verification.json
python3 scripts/engine/package_sources.py --output /tmp/BetterVMAF-engine-source.zip
```

The recipe pins full Git revisions, rejects source modifications, records configure arguments and toolchain identity, copies models/notices, ad-hoc signs the helpers, and writes SHA-256 hashes. `--stage-only` packages an already completed build at the selected cache. The procedure is reproducible; binary byte identity across different SDK/compiler versions is not claimed.

Two build integration details matter: the recipe sets `SDKROOT` from the selected Xcode explicitly (this host's newer Command Line Tools SDK was incompatible with its selected linker), and links static libvmaf with `-lc++` because its libsvm implementation needs the system C++ runtime. Neither adjustment patches metric code.

`verify.py` resolves every helper by absolute path and runs with a system-only PATH. It verifies manifest hashes, executable modes, arm64 architecture, signatures, system-only dependencies, filters, ffprobe JSON and software AV1 availability. Generated inputs exercise all eight VMAF v1 models, identity, nontrivial blur/chroma damage, native upstream CLI parity, original encode geometry/bitdepth, CAMBI source/full-reference output, XPSNR orientation and infinity. The upstream libvmaf Meson suite passed 22/22 tests; build outputs retain its full log. These are native host checks, not proof of execution on a separate pristine Mac or on macOS 15.2.

## Resource and filter contract

Bundle the `engine` directory intact, not as flattened individual Xcode resources:

- `engine/ffmpeg`, `engine/ffprobe`: production helpers.
- `engine/vmaf`: independent upstream CLI used for reproducible conformance checks.
- `engine/models/*.json`: eight v1.0.16 standard/HFR models and explicit legacy `vmaf_v0.6.1neg.json`.
- `engine/manifest.json`, `engine/licenses/*`: identity, checksums and redistribution notices.

Resolve the bundled executables only; missing or altered resources are errors, never a reason to substitute a system executable. Copy the selected model into a job-owned directory as `model.json`; use safe fixed relative output filenames. Inputs themselves are separate `Process` arguments. The following is the actual filter argument string (one backslash before each inner colon); input 0 is reference and input 1 distorted. Both inputs already have the same 10-bit SDR comparison canvas and valid paired timestamps:

```text
[1:v][0:v]libvmaf=model='path=model.json\:cambi.enc_width=640\:cambi.enc_height=360\:cambi.enc_bitdepth=10':feature='name=cambi\:full_ref=true\:enc_width=640\:enc_height=360\:enc_bitdepth=10\:src_width=640\:src_height=360':n_threads=4:log_fmt=json:log_path=vmaf.json
```

Use the original pre-upscale encode dimensions/precision in both `model` and diagnostic `feature` options. The tested 320×240 8-bit encode upscaled to a 640×360 10-bit canvas produces the expected `encbd_8`, `ench_240`, and `encw_320` output identity. Source dimensions likewise describe the original source. This upstream revision has no `src_bitdepth` option: retain original source bitdepth in result provenance, but do not pass an invented option. Its encoding dimension limits are width 180–7680 / height 150–7680; source limits are width 320–7680 / height 200–4320. Inputs outside them need an explicit unavailable result or validity rejection.

The diagnostic distorted CAMBI key is parameterized, for example `cambi_encbd_10_ench_360_encw_640_srch_360_srcw_640`; source and full-reference keys are `cambi_source` and `cambi_full_reference`. The model's internal CAMBI key is a separate instance, beginning `cambi_hrs_1080_cmxv_17_vlt_0.06...`. Do not use that value as the independently configured diagnostic score. Preserve source/encode scores and the nonnegative full-reference difference. Future libvmaf changes require rerunning key and parity checks.

XPSNR uses the opposite input orientation: `[0:v][1:v]xpsnr=stats_file=xpsnr.log`. Split the normalized inputs for a combined graph. Its stats file contains per-frame Y/U/V and a final `XPSNR average` line with upstream plane averages and their minimum. The final minimum is the upstream aggregate, not the minimum frame or an arithmetic mean computed by the app. Identity outputs `inf`; represent this explicitly rather than as zero or invalid JSON. Orientation fixture results differ: reference-first minimum 27.0939 dB; reversed 25.0961 dB. [Pinned upstream filter implementation](https://github.com/FFmpeg/FFmpeg/blob/9047fa1b084f76b1b4d065af2d743df1b40dfb56/libavfilter/vf_xpsnr.c)

## VMAF v1 compatibility and viewing assumptions

This exact post-release libvmaf revision still declares the project version as `3.2.0`; version-string comparison alone cannot identify compatibility. FFmpeg 8.1 plus this pinned revision executes all eight model files and supports the model feature overrides. On the native 10-bit blur/chroma fixture, primary VMAF mean is 88.825830 versus identity 100.000000. Every per-frame score agrees with the separately executed upstream `vmaf` CLI to the emitted six decimals (maximum absolute difference 0; tolerance 0.000001). This resolves the integration caveat for this tuple, without asserting that every build labeled 3.2.0 works.

The standard filenames are `vmaf_v1.0.16_3d0h.json` (1080p 3H), `vmaf_v1.0.16_5d0h.json` (phone 5H), `vmaf_v1.0.16_1d5h_2160.json` (4K 1.5H), and `vmaf_v1.0.16_3d0h_2160.json` (4K 3H). HFR filenames insert `_hfr` after `v1.0.16`. 4K 3H uses [0,110]; other profiles use [0,100]. Select viewing assumptions explicitly, not by the largest dimension being at least 2160. HFR profiles cover approximately 50/60 fps. [Pinned upstream model guidance](https://github.com/Netflix/vmaf/blob/f85a853692a8c730d0270cd733c8bb30b5b93b7c/resource/doc/models_v1.md)

The eight-profile executable probe uses a small deterministic fixture to test integration, not perceptual calibration at each target display resolution. SDR BT.709 normalization and correspondence are enforced by the app. PQ/HLG/HDR comparisons are unsupported. A model score is not retained-quality percentage or proof of transparency; film grain, high frame rate and perceptual encoding remain model limitations. Legacy results retain their original model identity and are not relabeled as v1.

## Distribution

Preserve all notices, including libsvm's BSD copyright and dav1d's AOM patent license. The app's MIT license does not cover these dependency components. `package_sources.py` verifies exact upstream source tar hashes and creates `BetterVMAF-engine-source.zip` with source trees, build/verification recipes, component manifest, and notices. The packaging command includes that companion inside the DMG; when publishing a separate companion download, keep it on the same release host. A missing archive cache is fetched at the exact pinned revision and verified before packaging. Do not rely only on moving upstream branch links for corresponding-source availability. The app invokes the standalone FFmpeg executable; it does not link proprietary app code into FFmpeg libraries. [Upstream distribution guidance](https://ffmpeg.org/legal.html)

Run `./create_dmg.sh` to build Release and validate a DMG, or pass `--app /absolute/path/Better\ VMAF.app` to validate an existing build. The script preserves verified helper signatures and signs the app, mounts the finished DMG read-only, reruns the native metric probe from its mounted resources, and writes `.manifest.json` and `.sha256` sidecars. The old Intel helper is removed only from staging after the replacement probe passes. Local packages use ad-hoc signing for execution without a paid account. They are not Developer ID signed or notarized. A clean-machine release run and actual minimum-OS testing remain separate release evidence, as do hardware/software decode parity, real-file cancellation/export and performance measurements.

When using `--app`, the Release app must embed the current Git revision: pass `BETTERVMAF_SOURCE_COMMIT=<git rev-parse HEAD>` to xcodebuild. The package validates this field against the checkout, records the executable hash, and explicitly applies/verifies the app sandbox and user-selected file entitlements. Normal `./create_dmg.sh` builds set the revision automatically.
