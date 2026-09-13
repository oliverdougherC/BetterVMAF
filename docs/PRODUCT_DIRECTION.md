# BetterVMAF: product positioning and comparison workflow

Research checked 2026-09-13 against primary project documentation and vendor pages. This is product research, not a hands-on performance or UX audit. Feature availability is documented, not independently exercised. Recommendations below are product judgments.

## Finding

There is room for a focused, approachable Mac encode-comparison app, but the category is not empty. The strongest direct counterexample is **Framewise**, already a free MIT-licensed native Swift/Metal macOS comparison app. Adding several familiar metrics also is not a unique feature by itself. BetterVMAF should distinguish itself through trustworthy input handling, easy interpretation, and a tight route from a concerning result to seeing the relevant scene.

Suggested positioning: **A free Mac app that shows what your encode changed, where it changed, and how much space you saved.** Keep “quality” grounded in evidence and visual comparison rather than claiming a universal quality score.

## Verified landscape

| Product | Mac/free/native distinction | Documented relevant capabilities | Implication for BetterVMAF |
|---|---|---|---|
| [Framewise](https://github.com/vork/Framewise) | MIT source; native Swift, Metal, AVFoundation, Core Image; macOS 14+ build instructions | Synchronized split slider, frame stepping, deep zoom, pixel readouts, error views, HDR handling; PSNR, SSIM/MS-SSIM, color difference, region exploration; optional compiled-in VMAF | Direct competitor to the proposed experience. Native + free + multiple metrics is already represented. Its README alone does not establish shipping reliability, metric validity, or measured smoothness. |
| [video-compare](https://github.com/pixop/video-compare) | GPLv2; Mac via Homebrew; C++/SDL2 desktop window launched from CLI, not Cocoa/SwiftUI | Synchronized visual comparison, wipe/subtraction, multiple candidates, manual timing offsets, frame controls, zoom, scopes, screenshots, hardware decoding options | Strong visual inspection baseline. BetterVMAF can remove command-line/setup friction and make a complete analytical run easier to interpret. |
| [FFMetrics](https://github.com/fifonik/FFMetrics) | Free; officially Windows/.NET, with externally supplied FFmpeg | VMAF, PSNR, SSIM, XPSNR; multi-file calculation, interactive frame plots, worst-frame PNG extraction, CSV output, VMAF model controls | Reference for batch metric workflows. Its own documentation warns about incorrect color-range transformations; correctness is a product opportunity. Do not call it a Mac competitor. |
| [ffmpeg-quality-metrics](https://github.com/slhck/ffmpeg-quality-metrics) | Open-source Python/FFmpeg tool for Linux/macOS/Windows; optional browser dashboard rather than native Mac UI | PSNR, SSIM, VMAF, VIF, MSAD; component values; JSON/CSV; delay handling; distribution plots, statistics and sortable frame tables through optional Plotly Dash GUI | Do not describe the current project as CLI-only. Useful reproducibility/export reference; no native playback experience is established by its documented dashboard. |
| [VQ Probe](https://vicuesoft.com/vq-probe/) | Mac/Windows/Linux advertised; vendor page calls it free, but current [official portal](https://portal.vicuesoft.com/) search-index content advertises paid Pro and trial; current free entitlement unresolved | Multiple metrics, two-video playback, difference heatmap, ROI, trim, loop, metric plots, RD curves and BD-rate | A significant existing professional comparison product. Avoid confidently calling all current functionality free. The portal exposes PSNR/SSIM/VMAF/CAMBI/CIEDE2000 for Pro. |
| [MSU VQMT](https://www.compression.ru/video/quality_measure/video_measurement_tool.html) | Windows GUI and Windows/Linux command line; personal-use free tier, paid professional tiers; no Mac version advertised | Many full/no-reference metrics, ROI, component and frame values, visualization, comparison, exports, optional GPU acceleration | Advanced analytical benchmark, but not a free native Mac workflow. Its page mixes older free-resolution wording with an explicit newer table allowing HD since 14.1; do not repeat the obsolete “free cannot do HD” claim. |
| [QCTools](https://mediaarea.net/QCTools) | Free/open source; Mac download and [Mac App Store listing](https://apps.apple.com/us/app/qctools/id1234563987?mt=12); Qt desktop UI | Preservation-oriented signal analysis, filtered playback, frame graphs, anomaly inspection and reports | Adjacent QC tool rather than primarily source-versus-encode perceptual scoring. Shows demand for connecting measurements to inspectable video. |
| [Video Commander](https://video-commander.com/) | Mac/Windows desktop app; Rust core with [React/Tauri interface](https://video-commander.com/playground); proprietary; [free personal use / $39 commercial license](https://video-commander.com/pricing) | Source/encode VMAF mean/min/max, timeline, frame comparison wipe/difference/blink, CSV/JSON and job history, plus broader encoding/inspection/delivery suite | Close workflow competition even without native Apple widgets. A focused comparison app can be easier to approach than a broad video engineering workspace, but that requires validation, not assumption. |
| [ffWorks](https://www.ffworks.net/) | macOS application; vendor lists €22 | Encoding workstation plus VMAF, PSNR, SSIM, CAMBI and bitrate analysis | Multi-metric Mac applications already exist at low prices. Free remains a differentiator against this product, not against the entire category. |
| [Telestream Switch](https://www.telestream.net/switch/overview.htm) | Commercial Mac/Windows media inspection product | Pro includes full/split/difference comparison against up to 16 alternate files, frame-accurate playback, bitrate/GOP views and scopes | Mature adjacent reference for visual inspection. Its documented comparison feature is not evidence of a VMAF-like multi-metric report. |

Framewise caveat: VMAF is opt-in at build time and its default build does not link it. The project documents current-frame region exploration and an error-over-time feature, but the research did not validate throughput, long-clip handling, shipped download availability or model conformance. That leaves meaningful engineering work for BetterVMAF, without proving Framewise fails those requirements. [Framewise documentation](https://github.com/vork/Framewise)

VQ Probe caveat: the marketing page and 2025 brochure call the tool free; the current portal's indexed text advertises Pro at €49/month or €529/year and a seven-day trial. Opening the portal returns a JavaScript shell. The safe statement is that Mac support and extensive comparison features are advertised, while current free-tier access remains uncertain. [Marketing page](https://vicuesoft.com/vq-probe/), [official portal](https://portal.vicuesoft.com/)

## Product direction

The default experience should answer three concrete questions:

1. **Did these files make a valid comparison?** Present reference and encode clearly, detect timing/dimension/color incompatibilities, and show a specific correction only when needed. An incomplete or misaligned comparison must not silently become a convincing summary.
2. **Where should I look?** Rank a few concerning time ranges and place them on one shared timeline. Selecting a range must seek both videos to the exact moment and offer a short loop. A jump to a generic results page is insufficient.
3. **Was the tradeoff useful?** Show file-size reduction and bitrate beside the visual evidence and metric profile. Savings are separate from perceptual quality; never improve the quality score simply because the file is smaller.

Suggested first results screen: a large synchronized viewer, one timeline with concern markers, a short “moments to review” list, and compact quality/savings summary. Surface the strongest evidence first. Allow the user to reveal exact metrics, percentile distributions, per-plane values, model settings and export details on demand.

Do not replace one unexplained number with five unexplained numbers. Prefer a quality profile with measurements that retain their names and units, explicit scope, and links to visual evidence. A disagreement between metrics is itself a useful inspection cue. Avoid declaring “excellent,” “visually lossless” or “invisible degradation” from invented cutoffs. If research later calibrates a composite, preserve the individual measurements and comparison context.

Group repeated low frames into scenes/time ranges rather than emitting dozens of nearly identical worst-frame cards. Distinguish a brief outlier from a sustained degradation. Show every-frame versus sampled analysis explicitly; sampled analysis cannot promise it found the worst moment.

Preserve the source display as the primary evidence. Difference maps exaggerate differences by design and belong behind a simple toggle with a gain indicator. A/B blink, wipe, synchronized zoom and looping have immediate practical value. Heatmaps should be named for what they compute (for example pixel difference); generic difference heatmaps are not maps of human annoyance.

A good initial scope is local source-versus-encode SDR comparison, independently validated metric outputs, and the shortest route from results to visual review. Add HDR assessment, film-grain-specific handling, multiple-encode decisions and heavier perceptual metrics in explicit later milestones. This is a sequencing recommendation, not an argument to flatten HDR silently or reject future support.

## Suggested implementation issues and acceptance evidence

| Work item | Acceptance evidence |
|---|---|
| Clear source/encode setup and validity checks | A known-good pair proceeds without configuration; known offset, duration, crop and metadata problems produce specific actionable states; no swapped inputs or silent repeated final frame. |
| One exact timeline across results and playback | Clicking every result marker seeks both files to its actual timestamp/frame mapping; frame-step, pause, loop, seek and zoom remain synchronized. |
| Guided review of degradation ranges | Adjacent concerning frames collapse into useful ranges; synthetic brief and sustained defects both appear; ties and metric disagreements are deterministic. |
| Progressive disclosure for metric details | Default screen works without knowing metric acronyms; exact values, units, models, ranges and exclusions remain available in details/export. No invented aggregate quality score. |
| Useful native interaction/performance | Drag/drop from Finder, keyboard playback controls, responsive cancellation and accessible controls; benchmark scrolling/seeking/playback on a named Mac and clip set rather than claiming smoothness from architecture. |
| Reproducible comparison record | Export preserves input identity, selected streams, timestamps, preprocessing, metric/model versions and raw results so another implementation can reproduce the run. |
| Compare against real alternatives | A small fixed task study against Framewise and video-compare, plus VQ Probe if accessible: time to open a pair, locate a known defect, inspect it, and save evidence. Report failures and limitations fairly. |

The product success criterion should be practical: a user can identify the size tradeoff, locate meaningful degradation, and judge it visually without needing to construct FFmpeg commands or learn the entire metric literature. A native implementation and an expanding metric count only support that outcome; they do not establish it alone.
