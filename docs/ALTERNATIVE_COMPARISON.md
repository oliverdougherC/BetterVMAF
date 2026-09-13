# Fixed-task comparison, 2026-09-13 UTC

This is a one-operator, one-pair engineering walkthrough on the Apple M4 Pro 24 GiB Mac used for [performance measurements](PERFORMANCE.md). It is not a user study, speed ranking, or comprehensive competitor review. Exact source commits, input hashes, observed outcomes and limitations are in [the machine-readable record](evidence/performance-alternative-study.json).

The fixed task was: open a source and encode, locate a known degradation interval, inspect the corresponding frames, and save evidence. The 48-frame 640×360 24fps pair is a generated MIT-licensed scene. The encode has full black frames 24–35, covering [1.0,1.5) seconds. Both review files use the same common 8-bit BT709 conversion and lossless H264 encoding; they are review derivatives, not the original 10-bit metric-conformance sources. Their commands and provenance live with the [corpus](CORPUS.md). The walkthrough preceded a later repair of the review derivatives’ missing primaries/transfer tags; the study JSON retains the hashes actually used. The corrected derivatives now at those paths are distinct input identities and have not retroactively replaced the observed files.

| Step | Framewise | video-compare | BetterVMAF |
|---|---|---|---|
| Obtain/run | Official source built successfully, native arm64, ad-hoc signing | Official source built successfully after selecting the matching Xcode SDK | Integrated review build is validated separately |
| Open pair | Two native open panels loaded both intended files | Runtime logs confirm both inputs decoded; native UI automation attachment failed | Both corrected review derivatives loaded |
| Locate defect | Error over time → Worst 0:01 selected zero-based frame 35, inside the injected interval | Not exercised; attachment blocked interaction | Concern selected frame 24 at 1.0s; Previous selected frame 23 |
| Inspect | Screenshot visibly showed source test pattern on left and black encode on right, burned-in timestamp 1.458/frame 35 | Not exercised | Both source/encode burned-in frame labels matched the selected frame |
| Save evidence | Tool screenshot captured in task transcript. No export item in File menu or screenshot/save handler found in this source revision | Documented F frame/viewport PNG export was not exercised | Native PDF and schema-1 JSON saved and verified |

Framewise was an effective reference for this task: the default sampled MAE timeline exposed the sustained defect and its Worst button sought into it. This observation does not establish detection of short/periodic defects, exact temporal synchronization on other inputs, or metric conformance. The native open-panel automation needed retries: observed wall time was 59.755 seconds to the loaded pair and 72.648 seconds from first action to inspected defect. These figures include tool orchestration delays and are deliberately not compared with human performance or another app.

The inspected Framewise build script at commit `e56c4dc713b097cf9b8e816d12cc8dbf89634388` **enables static libvmaf 3.1.0 by default**. This supersedes the earlier product-research statement that VMAF was opt-in. The build emitted version 0.7.0. [Pinned build script](https://github.com/vork/Framewise/blob/e56c4dc713b097cf9b8e816d12cc8dbf89634388/build.sh).

video-compare commit `dcdbefcdf7900659cb1a1f2631edbccfdcb1398c` identified itself as 20260828-reykjavik. Its documented CLI and inspection controls remain useful comparison references. The first build encountered a local CLT macOS 27 SDK/Xcode linker mismatch; using Xcode 26.5 SDK fixed it. The running SDL app then could not be attached through the available native automation tool: app-path and bundle-ID attachment both timed out. The input decoder log confirmed both intended H264 streams. This is a recorded test-harness limitation; it does **not** demonstrate that video-compare failed the visual task. [Pinned source/controls](https://github.com/pixop/video-compare/tree/dcdbefcdf7900659cb1a1f2631edbccfdcb1398c).

## Reproduce

Keep third-party clones and generated media outside Git history. Build Framewise from its pinned official source with `./build.sh` (meson, ninja, nasm prerequisites). Build video-compare from its pinned source with `make -j4 USE_PKG_CONFIG=1`; select a compiler and SDK from the same installed Xcode. SDL2/SDL2_ttf and FFmpeg development libraries are build prerequisites.

Run video-compare with the corpus review pair:

```sh
video-compare -w 1280x720 /path/to/review_reference.mp4 /path/to/review_sustained.mp4
```

The integrated BetterVMAF pass used the regenerated, corrected review derivatives, whose identities differ from the earlier Framewise walkthrough. The parent operator selected frame 24 at 1.0s inside the known defect and stepped back to matching source/encode frame 23. After repairing the native sandbox destination workflow, the UI owner saved a 27,225-byte one-page PDF and a 67,406-byte schema-1 JSON with all 48 samples. The PDF was rendered and visually inspected by that owner; this lane independently checked the saved JSON and artifact hashes. Exact input/output identities and local evidence paths are recorded in the study JSON. This establishes the fixed task’s outcomes, not same-file metric conformance, a shorter workflow, or better performance. A follow-up human walkthrough should use counterbalanced app order, identical input placement, successful native evidence saving and repeated trials before making timing claims.
