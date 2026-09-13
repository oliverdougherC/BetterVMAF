#!/usr/bin/env python3
import argparse, json, pathlib, subprocess, hashlib, time, re, os, signal
import numpy as np
import pyexr

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
A = P.parse_args()
O = A.root / "ssimulacra2"
B = A.root / "upstream/libjxl/build/tools"
results = []


def measure(cmd):
    t = time.perf_counter()
    p = subprocess.run(
        ["/usr/bin/time", "-l", *map(str, cmd)], capture_output=True, text=True
    )
    m = re.search(r"(\d+)\s+maximum resident set size", p.stderr)
    return dict(
        command=list(map(str, cmd)),
        seconds=time.perf_counter() - t,
        peak_rss_bytes=int(m.group(1)) if m else None,
        returncode=p.returncode,
        score=float(p.stdout.strip()) if p.returncode == 0 else None,
        stderr=p.stderr,
    )


for w, h in [(640, 360), (1920, 1080), (3840, 2160)]:
    for name in ["ref", "color"]:
        arr = pyexr.read(str(O / f"{name}_{w}.exr"))
        (O / f"{name}_{w}.f32").write_bytes(arr.astype("<f4").tobytes())
    r = O / f"ref_{w}"
    d = O / f"color_{w}"
    ref = measure([B / "ssimulacra2", str(r) + ".exr", str(d) + ".exr"])
    raw = measure([B / "ssimulacra2_linear", w, h, str(r) + ".f32", str(d) + ".f32"])
    results.append(
        dict(
            size=[w, h],
            reference=ref,
            adapter=raw,
            difference=abs(ref["score"] - raw["score"]),
        )
    )
# Validated BT.709 limited 10-bit gray ramp decode into float32 linear-sRGB.
source = A.root / "generated/gradient.mkv"
w, h = 640, 360
cmd = [
    "ffmpeg",
    "-v",
    "error",
    "-i",
    str(source),
    "-frames:v",
    "1",
    "-vf",
    "zscale=transfer=linear:primaries=bt709:matrix=gbr:range=full,format=gbrpf32le",
    "-f",
    "rawvideo",
    "-",
]
buf = subprocess.check_output(cmd)
gbr = np.frombuffer(buf, dtype="<f4").reshape(3, h, w)
rgb = np.stack([gbr[2], gbr[0], gbr[1]], 2)
yuv = subprocess.check_output(
    [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(source),
        "-frames:v",
        "1",
        "-pix_fmt",
        "yuv420p10le",
        "-f",
        "rawvideo",
        "-",
    ]
)
luma = np.frombuffer(yuv, dtype="<u2", count=w * h).reshape(h, w)
e = (luma.astype(np.float32) - 64) / 876
expected = np.where(e < 0.081, e / 4.5, ((e + 0.099) / 1.099) ** (1 / 0.45))
scene_error = float(np.max(abs(rgb[:, :, 0] - expected)))
display_expected = e**2.4
error = float(np.max(abs(rgb[:, :, 0] - display_expected)))
pyexr.write(str(O / "decoded_linear.exr"), rgb)
(O / "decoded_linear.f32").write_bytes(rgb.astype("<f4").tobytes())
managed = measure(
    [
        B / "ssimulacra2_linear",
        640,
        360,
        O / "decoded_linear.f32",
        O / "decoded_linear.f32",
    ]
)
# Signed score and invalid input guards.
neg = 1 - pyexr.read(str(O / "ref_640.exr"))
(O / "negative.f32").write_bytes(neg.astype("<f4").tobytes())
signed = measure(
    [B / "ssimulacra2_linear", 640, 360, O / "ref_640.f32", O / "negative.f32"]
)
(O / "truncated.f32").write_bytes(b"\0" * 16)
truncated = measure(
    [B / "ssimulacra2_linear", 640, 360, O / "truncated.f32", O / "ref_640.f32"]
)
p = subprocess.Popen(
    [
        str(B / "ssimulacra2_linear"),
        "3840",
        "2160",
        str(O / "ref_3840.f32"),
        str(O / "color_3840.f32"),
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    start_new_session=True,
)
time.sleep(0.05)
running = p.poll() is None
t = time.perf_counter()
os.killpg(p.pid, signal.SIGTERM)
p.communicate(timeout=10)
cancel = dict(
    active_before_cancel=running,
    seconds=time.perf_counter() - t,
    returncode=p.returncode,
)
output = dict(
    schema=1,
    source_revision="a7a9c787341cf703dede03c2009fa460cae5e5df",
    build_script="scripts/experiments/build_ssimulacra2.sh",
    helper_sha256=hashlib.sha256((B / "ssimulacra2_linear").read_bytes()).hexdigest(),
    helper_bytes=(B / "ssimulacra2_linear").stat().st_size,
    architecture=subprocess.check_output(
        ["file", str(B / "ssimulacra2_linear")]
    ).decode(),
    dependencies=subprocess.check_output(
        ["otool", "-L", str(B / "ssimulacra2_linear")]
    ).decode(),
    results=results,
    managed_decode=dict(
        command=cmd,
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        analytical_bt1886_display_max_abs_error=error,
        scene_inverse_oetf_max_abs_difference=scene_error,
        transfer_contract="Display-referred BT.709 uses ideal BT.1886 gamma2.4 in zimg; scene-referred inverse camera OETF is a different contract.",
        gray_threshold=0.0001,
        identity=managed,
        scope="Gray ramp tests transfer/range; gamut/chroma interpolation not fully qualified for app.",
    ),
    signed=signed,
    truncated=truncated,
    cancellation=cancel,
    tolerance=1e-6,
    tolerance_reason="Same pinned upstream implementation, float32 arrays, architecture and CMS; JSON roundoff8decimals. This is conformance, not perceptual confidence.",
)
(O / "conformance.json").write_text(json.dumps(output, indent=2) + "\n")
print(json.dumps(output, indent=2))
assert all(r["difference"] <= 1e-6 for r in results)
assert error < 0.0001 and managed["score"] == 100
assert signed["score"] < 0 and truncated["returncode"] != 0
assert cancel["active_before_cancel"] and cancel["returncode"] < 0
