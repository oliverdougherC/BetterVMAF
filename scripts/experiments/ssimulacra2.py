#!/usr/bin/env python3
"""Reference-only SSIMULACRA2 color/precision/resource gate; never app scores."""

import argparse, hashlib, json, pathlib, subprocess, time, resource, struct, zlib, os, signal
import numpy as np
import pyexr

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
P.add_argument("--helper", default="/opt/homebrew/opt/jpeg-xl/bin/ssimulacra2")
A = P.parse_args()
O = A.root / "ssimulacra2"
O.mkdir(exist_ok=True)


def png16(p, x, gamma):
    h, w, _ = x.shape

    def chunk(t, b):
        return (
            struct.pack(">I", len(b))
            + t
            + b
            + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
        )

    a = np.round(np.clip(x, 0, 1) * 65535).astype(">u2")
    rows = b"".join(b"\x00" + r.tobytes() for r in a)
    p.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 2, 0, 0, 0))
        + chunk(b"gAMA", struct.pack(">I", gamma))
        + chunk(
            b"cHRM",
            struct.pack(">8I", 31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000),
        )
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def run(label, r, d):
    cmd = [A.helper, str(r), str(d)]
    t = time.perf_counter()
    u = resource.getrusage(resource.RUSAGE_CHILDREN)
    proc = subprocess.run(["/usr/bin/time", "-l", *cmd], capture_output=True, text=True)
    elapsed = time.perf_counter() - t
    v = resource.getrusage(resource.RUSAGE_CHILDREN)
    import re

    m = re.search(r"(\d+)\s+maximum resident set size", proc.stderr)
    return dict(
        label=label,
        command=cmd,
        returncode=proc.returncode,
        score=float(proc.stdout.strip()) if proc.returncode == 0 else None,
        seconds=elapsed,
        peak_rss_bytes=int(m.group(1)) if m else None,
        cpu_seconds=v.ru_utime + v.ru_stime - u.ru_utime - u.ru_stime,
        diagnostics=proc.stderr[-2000:],
    )


def srgb(x):
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


results = []
for w, h in [(640, 360), (1920, 1080), (3840, 2160)]:
    y, x = np.mgrid[0:h, 0:w]
    x = x / (w - 1)
    y = y / (h - 1)
    ref = np.stack(
        [
            0.01 + 0.75 * x,
            0.02 + 0.70 * y,
            0.03 + 0.5 * (np.sin(x * 60) * np.cos(y * 50) + 1) / 2,
        ],
        2,
    ).astype(np.float32)
    dis = ref.copy()
    dis[:, :, 0] *= 0.8
    dis[:, :, 2] = np.minimum(dis[:, :, 2] * 1.2, 1)
    rp = O / f"ref_{w}.exr"
    dp = O / f"color_{w}.exr"
    pyexr.write(str(rp), ref)
    pyexr.write(str(dp), dis)
    for repeat in range(3):
        results.append(run(f"{w}x{h}_color_{repeat}", rp, dp))
    if w == 640:
        results.append(run("identity_float32", rp, rp))
        neg = O / "negative.exr"
        pyexr.write(str(neg), 1 - ref)
        results.append(run("severe_signed", rp, neg))
        # PNG explicit gamma=1 is linear sRGB; EXR defaults linear sRGB in upstream.
        pl = O / "ref_linear16.png"
        dl = O / "color_linear16.png"
        png16(pl, ref, 100000)
        png16(dl, dis, 100000)
        results.append(run("linear16_vs_float_reference", pl, rp))
        results.append(run("linear16_color", pl, dl))
        # PFM defaults to sRGB in libjxl. It is correct here only because input is encoded sRGB.
        for name, arr in [("ref", ref), ("color", dis)]:
            (O / (name + ".pfm")).write_bytes(
                f"PF\n{w} {h}\n-1.0\n".encode()
                + np.flipud(srgb(arr)).astype("<f4").tobytes()
            )
        results.append(run("srgb_float_color", O / "ref.pfm", O / "color.pfm"))
        # Identical numeric codes with changed transfer metadata must NOT be identity.
        wrong = O / "ref_wronggamma16.png"
        png16(wrong, ref, 45455)
        results.append(run("metadata_transfer_difference", pl, wrong))
# Cancel a real active 4K computation; await process exit and verify it is gone.
p = subprocess.Popen(
    [A.helper, str(O / "ref_3840.exr"), str(O / "color_3840.exr")],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    start_new_session=True,
)
time.sleep(0.05)
was_running = p.poll() is None
t = time.perf_counter()
os.killpg(p.pid, signal.SIGTERM)
p.communicate(timeout=10)
cancel = dict(
    was_running=was_running, seconds=time.perf_counter() - t, returncode=p.returncode
)
version = subprocess.run(
    ["otool", "-L", A.helper], capture_output=True, text=True
).stdout
output = dict(
    schema=1,
    hardware="Apple M4 Pro 14 cores / 24 GB",
    macos="27.0 (26A428)",
    upstream="libjxl v0.12.0 / SSIMULACRA2 v2.1",
    revision="a7a9c787341cf703dede03c2009fa460cae5e5df",
    helper_sha256=hashlib.sha256(pathlib.Path(A.helper).read_bytes()).hexdigest(),
    helper_bytes=pathlib.Path(A.helper).stat().st_size,
    dependencies=version,
    results=results,
    cancellation=cancel,
    energy="CPU time measured; powermetrics requires privileged access and was not available. No energy/battery claim.",
    input_hashes={
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in O.iterdir()
        if p.is_file() and p.suffix in {".exr", ".png", ".pfm"}
    },
)
(O / "results.json").write_text(json.dumps(output, indent=2) + "\n")
print(json.dumps({"results": results, "cancellation": cancel}, indent=2))
assert all(x["returncode"] == 0 for x in results)
assert next(x["score"] for x in results if x["label"] == "severe_signed") < 0
assert next(x["score"] for x in results if x["label"] == "identity_float32") == 100
assert cancel["was_running"] and cancel["returncode"] < 0
