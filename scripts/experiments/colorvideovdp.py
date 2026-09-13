#!/usr/bin/env python3
"""Measured upstream HDR/temporal investigation on explicit float RGB arrays."""

import argparse, hashlib, json, pathlib, platform, resource, time
import numpy as np
import torch
import pycvvdp

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
P.add_argument("--device", choices=["cpu", "mps"], default="mps")
P.add_argument("--width", type=int, default=320)
P.add_argument("--frames", type=int, default=24)
P.add_argument(
    "--cases", default="identity,chroma,brief_flicker,periodic_flicker,sustained,freeze"
)
A = P.parse_args()
torch.set_num_threads(4)
O = A.root / "colorvideovdp"
O.mkdir(exist_ok=True)
results = []
fps = 24
w = A.width
h = w * 9 // 16
n = A.frames
# Linear-light BT.2020 synthetic moving RGB ramp (scene samples 0.002..1).
y, x = np.mgrid[0:h, 0:w]
x = x / (w - 1)
y = y / (h - 1)
base = np.stack(
    [
        0.01 + 0.65 * x,
        0.02 + 0.65 * y,
        0.03 + 0.4 * (1 + np.sin(x * 40) * np.cos(y * 30)) / 2,
    ],
    2,
)
linear = np.stack([np.roll(base, i * 3, axis=1) for i in range(n)], axis=3).astype(
    np.float32
)


def encode(a, transfer):
    if transfer == "pq":
        q = np.power(np.clip(a * 1000 / 10000, 0, 1), 2610 / 16384)
        return np.power(
            (3424 / 4096 + (2413 / 128) * q) / (1 + (2392 / 128) * q), 2523 / 32
        ).astype(np.float32)
    aa = 0.17883277
    bb = 1 - 4 * aa
    cc = 0.5 - aa * np.log(4 * aa)
    return np.where(
        a <= 1 / 12, np.sqrt(3 * a), aa * np.log(np.maximum(12 * a - bb, 1e-9)) + cc
    ).astype(np.float32)


for transfer in ["pq", "hlg"]:
    reference = encode(linear, transfer)
    display = "standard_hdr_" + transfer
    t = time.perf_counter()
    metric = pycvvdp.cvvdp(
        display_name=display, device=torch.device(A.device), heatmap=None
    )
    setup = time.perf_counter() - t
    for case in A.cases.split(","):
        distorted = linear.copy()
        if case == "chroma":
            distorted[:, :, 0, :] *= 0.8
            distorted[:, :, 2, :] *= 1.15
        elif case == "brief_flicker":
            distorted[:, :, :, n // 2] *= 0.5
        elif case == "periodic_flicker":
            distorted[:, :, :, 3::6] *= 0.5
        elif case == "sustained":
            distorted[:, :, :, n // 3 : 2 * n // 3] *= 0.5
        elif case == "freeze":
            distorted[:, :, :, n // 2 :] = distorted[:, :, :, n // 2 : n // 2 + 1]
        test = encode(distorted, transfer)
        if A.device == "mps":
            torch.mps.synchronize()
        t = time.perf_counter()
        cpu = time.process_time()
        score, stats = metric.predict(
            test, reference, dim_order="HWCF", frames_per_second=fps
        )
        if A.device == "mps":
            torch.mps.synchronize()
        elapsed = time.perf_counter() - t
        row = dict(
            transfer=transfer,
            case=case,
            display=display,
            device=A.device,
            width=w,
            height=h,
            frames=n,
            fps=fps,
            score_jod=float(score),
            seconds=elapsed,
            evaluated_fps=n / elapsed,
            cpu_seconds=time.process_time() - cpu,
            process_peak_rss_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            setup_seconds=setup,
            reference_sha256=hashlib.sha256(reference.tobytes()).hexdigest(),
            test_sha256=hashlib.sha256(test.tobytes()).hexdigest(),
            mps_allocated_bytes=torch.mps.current_allocated_memory()
            if A.device == "mps"
            else None,
            mps_driver_bytes=torch.mps.driver_allocated_memory()
            if A.device == "mps"
            else None,
        )
        results.append(row)
        print(json.dumps(row), flush=True)
        del score, stats
    del metric
    if A.device == "mps":
        torch.mps.empty_cache()
output = dict(
    schema=1,
    upstream_revision="2a268bce8d56e2f3abde46df3927d8a633707a24",
    cvvdp="0.5.7",
    torch=torch.__version__,
    platform=platform.platform(),
    mps_available=torch.backends.mps.is_available(),
    display_assumptions=dict(
        gamut="BT.2020",
        peak_luminance_cd_m2=1500,
        contrast=1000000,
        ambient_lux=10,
        diagonal_inches=30,
        resolution=[3840, 2160],
        distance_m=0.7472,
        source_pq_peak_cd_m2=1000,
        hlg="BT.2100 OETF scene values; upstream display-specific OOTF",
    ),
    results=results,
    energy="CPU time and MPS allocation are observations, not joule/battery measurements. powermetrics needs unavailable elevated privileges.",
)
(O / f"{A.device}_{w}_{n}.json").write_text(json.dumps(output, indent=2) + "\n")
assert all(np.isfinite(r["score_jod"]) for r in results)
