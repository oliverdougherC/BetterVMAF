#!/usr/bin/env python3
"""Seeded blinded still-frame audit; images are visual aids, never metric inputs."""

import argparse, json, pathlib, random, subprocess, io, hashlib
from PIL import Image, ImageDraw

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
A = P.parse_args()
R = A.root
O = R / "visual_review"
O.mkdir(exist_ok=True)
rng = random.Random(531)
cases = ["identity", "gamma", "uv_corrupt", "oversharpen"]
rng.shuffle(cases)
out = Image.new("RGB", (1280, 4 * 390))
draw = ImageDraw.Draw(out)
key = []
for i, case in enumerate(cases):
    pair = ["motion24", case]
    rng.shuffle(pair)
    key.append({"row": chr(65 + i), "left": pair[0], "right": pair[1], "pts": 0.75})
    for c, name in enumerate(pair):
        cmd = [
            "ffmpeg",
            "-v",
            "error",
            "-ss",
            "0.75",
            "-i",
            str(R / "generated" / (name + ".mkv")),
            "-frames:v",
            "1",
            "-f",
            "image2pipe",
            "-c:v",
            "png",
            "-",
        ]
        b = subprocess.check_output(cmd)
        image = Image.open(io.BytesIO(b)).convert("RGB")
        out.paste(image, (c * 640, i * 390 + 30))
    draw.text((10, i * 390 + 8), "Pair " + chr(65 + i), fill="white")
out.save(O / "blinded_pairs.png")
(O / "key.json").write_text(
    json.dumps(
        {
            "seed": 531,
            "rows": key,
            "sha256": hashlib.sha256(
                (O / "blinded_pairs.png").read_bytes()
            ).hexdigest(),
        },
        indent=2,
    )
    + "\n"
)
# Scene selection review: public excerpts, not black credit cards.
canvas = Image.new("RGB", (640, 4 * 190))
draw = ImageDraw.Draw(canvas)
for i, name in enumerate([f"{x}_{n}" for x in ["bbb", "tears"] for n in range(1, 5)]):
    cmd = [
        "ffmpeg",
        "-v",
        "error",
        "-ss",
        "0.75",
        "-i",
        str(R / "generated" / (name + ".mkv")),
        "-frames:v",
        "1",
        "-vf",
        "scale=320:160:force_original_aspect_ratio=decrease",
        "-f",
        "image2pipe",
        "-c:v",
        "png",
        "-",
    ]
    b = subprocess.check_output(cmd)
    image = Image.open(io.BytesIO(b))
    xx = i % 2 * 320
    yy = i // 2 * 190
    canvas.paste(image, (xx, yy + 20))
    draw.text((xx + 10, yy + 4), name, fill="white")
canvas.save(O / "source_selection.jpg")
print(O)
