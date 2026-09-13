#!/usr/bin/env python3
"""Score valid frozen corpus pairs with the pinned shipped Standard metric tuple."""

import argparse, hashlib, json, pathlib, shutil, subprocess, time, re

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
P.add_argument("--engine", type=pathlib.Path, required=True)
A = P.parse_args()
A.root = A.root.resolve()
E = A.engine.resolve()
O = A.root / "metrics"
O.mkdir(exist_ok=True)
M = json.loads((A.root / "generated/manifest.json").read_text())
rows = []
valid = {"valid"}
for record in M["records"]:
    if record.get("expected_policy") not in valid:
        continue
    source = record["source"]
    reference = next((r for r in M["records"] if r["id"] == source), record)
    ref = A.root / reference["path"]
    dis = A.root / record["path"]
    for entry, path in [(reference, ref), (record, dis)]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"Source changed since generation: {path}")
    rstream = reference["probe"]["streams"][0]
    dstream = record["probe"]["streams"][0]
    w = dstream["width"]
    h = dstream["height"]
    sw = rstream["width"]
    sh = rstream["height"]
    bd = 10 if "10" in dstream["pix_fmt"] else 8
    dest = O / record["id"]
    dest.mkdir(exist_ok=True)
    shutil.copy2(E / "models/vmaf_v1.0.16_3d0h.json", dest / "model.json")
    # Staged relative names isolate FFmpeg filter grammar from arbitrary user paths.
    for name, path in [("reference.mkv", ref), ("distorted.mkv", dis)]:
        p = dest / name
        if p.is_symlink():
            p.unlink()
        if p.exists():
            raise ValueError(f"Refusing to replace non-staged file: {p}")
        p.symlink_to(path)
    pre = "format=yuv420p10le"
    graph = f"[0:v]{pre},split=2[r1][r2];[1:v]{pre},split=2[d1][d2];[d1][r1]libvmaf=model='path=model.json\\:cambi.enc_width={w}\\:cambi.enc_height={h}\\:cambi.enc_bitdepth={bd}':feature='name=cambi\\:full_ref=true\\:enc_width={w}\\:enc_height={h}\\:enc_bitdepth={bd}\\:src_width={sw}\\:src_height={sh}':n_threads=4:log_fmt=json:log_path=vmaf.json:shortest=1:repeatlast=0[v];[r2][d2]xpsnr=stats_file=xpsnr.log:shortest=1:repeatlast=0[x]"
    cmd = [
        str(E / "ffmpeg"),
        "-hide_banner",
        "-nostdin",
        "-filter_complex_threads",
        "2",
        "-i",
        "reference.mkv",
        "-i",
        "distorted.mkv",
        "-filter_complex",
        graph,
        "-map",
        "[v]",
        "-map",
        "[x]",
        "-an",
        "-f",
        "null",
        "-",
    ]
    t = time.perf_counter()
    p = subprocess.run(
        ["/usr/bin/time", "-l", *cmd], cwd=dest, capture_output=True, text=True
    )
    (dest / "stderr.log").write_text(p.stderr)
    stats = dict(returncode=p.returncode, seconds=time.perf_counter() - t, command=cmd)
    if p.returncode == 0:
        vm = json.loads((dest / "vmaf.json").read_text())
        stats["pooled_metrics"] = vm["pooled_metrics"]
        stats["frames"] = len(vm["frames"])
        stats["version"] = vm.get("version")
        stats["frame_values"] = vm["frames"]
        xm = re.findall(r"XPSNR average[^\n]*", (dest / "xpsnr.log").read_text())
        stats["xpsnr_upstream_aggregate"] = xm
        rss = re.search(r"(\d+)\s+maximum resident set size", p.stderr)
        stats["peak_rss_bytes"] = int(rss.group(1)) if rss else None
    else:
        stats["error"] = p.stderr[-4000:]
    (dest / "run.json").write_text(json.dumps(stats, indent=2) + "\n")
    stats["id"] = record["id"]
    stats["reference_sha256"] = reference["sha256"]
    stats["distorted_sha256"] = record["sha256"]
    rows.append(stats)
    print(record["id"], stats["returncode"], round(stats["seconds"], 3), flush=True)
manifest = dict(
    schema=1,
    engine_sha256=hashlib.sha256((E / "ffmpeg").read_bytes()).hexdigest(),
    model_sha256=hashlib.sha256(
        (E / "models/vmaf_v1.0.16_3d0h.json").read_bytes()
    ).hexdigest(),
    hardware="Apple M4 Pro 24GB, macOS 27.0 (26A428)",
    preprocessing="Both inputs format yuv420p10le; all selected fixtures same geometry/cadence, tagged BT.709 limited. No hidden spatial/cadence/transfer transform. Original encode depth persisted for CAMBI.",
    rows=rows,
)
(O / "results.json").write_text(json.dumps(manifest, indent=2) + "\n")
assert all(r["returncode"] == 0 for r in rows)
