#!/usr/bin/env python3
"""Replay sample selection on actual full scores; no subsampled metric rerender."""

import argparse, json, pathlib, random, statistics, subprocess, time, shutil

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
P.add_argument("--engine", type=pathlib.Path, required=True)
A = P.parse_args()
O = A.root / "quick_scan"
O.mkdir(exist_ok=True)
M = json.loads((A.root / "metrics/results.json").read_text())
rng = random.Random(544)
# A fixed stride fails periodic frame5+12k damage; stratification isn't a guarantee.
centers = {
    "full": list(range(48)),
    "stride12": list(range(0, 48, 12)),
    "stratified_seed544": [rng.randrange(i, min(i + 12, 48)) for i in range(0, 48, 12)],
    "scene_boundaries": [0, 24, 47],
}
truth = {
    "damage_brief": [13],
    "damage_periodic": [5, 17, 29, 41],
    "damage_sustained": list(range(24, 36)),
}
rows = []
for case, defects in truth.items():
    full = next(r for r in M["rows"] if r["id"] == case)
    scores = [r["metrics"]["vmaf"] for r in full["frame_values"]]
    for method, selected in centers.items():
        # Retain whole original cadence for metric evaluation in this experiment.
        # Context below is the proposed decoded coverage, NOT re-evaluated samples.
        context = sorted(
            {j for i in selected for j in range(max(0, i - 2), min(48, i + 3))}
        )
        hit = sorted(set(selected) & set(defects))
        context_hit = sorted(set(context) & set(defects))
        expanded = sorted(
            set(selected)
            | {
                j
                for i in selected
                if scores[i] < 80
                for j in range(max(0, i - 6), min(48, i + 7))
            }
        )
        rows.append(
            dict(
                case=case,
                method=method,
                seed=544 if "seed" in method else None,
                selected_frames=selected,
                proposed_context_frames=context,
                expanded_frames=expanded,
                scored_coverage=len(selected) / 48,
                proposed_decoded_coverage=len(context) / 48,
                scored_seconds=len(selected) / 24,
                defect_frames=defects,
                hit_frames=hit,
                context_hit_frames=context_hit,
                expanded_hit_frames=sorted(set(expanded) & set(defects)),
                sampled_mean=statistics.mean(scores[i] for i in selected),
                sampled_min=min(scores[i] for i in selected),
                full_mean=statistics.mean(scores),
                full_min=min(scores),
                full_metric_seconds=full["seconds"],
                sample_runtime_seconds=None,
            )
        )
# Execute contiguous context windows with original cadence; compare retained centers.
for row in rows:
    if row["method"] == "full":
        continue
    window_frames = row["proposed_context_frames"]
    windows = []
    for i in window_frames:
        if windows and i == windows[-1][1]:
            windows[-1][1] = i + 1
        else:
            windows.append([i, i + 1])
    full = next(r for r in M["rows"] if r["id"] == row["case"])
    fullscores = [r["metrics"]["vmaf"] for r in full["frame_values"]]
    measured = {}
    t = time.perf_counter()
    for lo, hi in windows:
        dest = O / (row["case"] + "_" + row["method"] + f"_{lo}_{hi}")
        dest.mkdir(exist_ok=True)
        shutil.copy2(A.engine / "models/vmaf_v1.0.16_3d0h.json", dest / "model.json")
        graph = f"[0:v]trim=start_frame={lo}:end_frame={hi},setpts=PTS-STARTPTS,format=yuv420p10le[r];[1:v]trim=start_frame={lo}:end_frame={hi},setpts=PTS-STARTPTS,format=yuv420p10le[d];[d][r]libvmaf=model='path=model.json\\:cambi.enc_width=640\\:cambi.enc_height=360\\:cambi.enc_bitdepth=10':n_threads=4:log_fmt=json:log_path=window.json:shortest=1:repeatlast=0"
        cmd = [
            str(A.engine.resolve() / "ffmpeg"),
            "-v",
            "error",
            "-nostdin",
            "-filter_complex_threads",
            "2",
            "-i",
            str(A.root.resolve() / "generated/motion24.mkv"),
            "-i",
            str(A.root.resolve() / "generated" / (row["case"] + ".mkv")),
            "-filter_complex",
            graph,
            "-an",
            "-f",
            "null",
            "-",
        ]
        subprocess.run(cmd, cwd=dest, check=True, capture_output=True)
        for frame in json.loads((dest / "window.json").read_text())["frames"]:
            measured[lo + frame["frameNum"]] = frame["metrics"]["vmaf"]
        (dest / "command.json").write_text(json.dumps(cmd, indent=2) + "\n")
    row["sample_runtime_seconds"] = time.perf_counter() - t
    row["executed_context_windows"] = windows
    row["selected_context_scores"] = {
        str(i): measured[i] for i in row["selected_frames"]
    }
    row["max_selected_difference_from_full"] = max(
        abs(measured[i] - fullscores[i]) for i in row["selected_frames"]
    )
output = dict(
    schema=1,
    description="Selection replay and actual contiguous-window runs compared against real full-sequence VMAF v1. Windows preserve original24fps and include +/-2 neighboring frames, merge overlaps, and retain only selected centers for sampled statistics. Exact window results and commands remain external. HFR smoothing and VFR require separate validation before production.",
    seed=544,
    frames=48,
    fps=24,
    rows=rows,
    decision="Defer Quick UI. Fixed stride misses brief and periodic damage entirely; stratification and scene boundaries also miss brief damage. Expansion cannot discover a defect with no initial signal. Keep Full Standard.",
)
(O / "results.json").write_text(json.dumps(output, indent=2) + "\n")
print(json.dumps(rows, indent=2))
assert (
    next(
        r for r in rows if r["case"] == "damage_periodic" and r["method"] == "stride12"
    )["hit_frames"]
    == []
)
assert all(r["scored_coverage"] <= 1 for r in rows)
