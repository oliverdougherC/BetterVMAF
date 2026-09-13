#!/usr/bin/env python3
"""Generate licensed, deterministic engineering scenes and adversity matrix outside Git."""

import argparse, hashlib, json, pathlib, subprocess, zipfile

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
P.add_argument("--ffmpeg", default="ffmpeg")
P.add_argument("--ffprobe", default="ffprobe")
P.add_argument("--synthetic-only", action="store_true")
A = P.parse_args()
R = A.root.resolve()
O = R / "generated"
O.mkdir(parents=True, exist_ok=True)
records = []


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def make(
    name,
    inputs,
    filters=None,
    extra=None,
    tags=None,
    source="synthetic",
    policy="valid",
    pix="yuv420p10le",
):
    out = O / (name + ".mkv")
    cmd = [
        A.ffmpeg,
        "-v",
        "error",
        "-nostdin",
        "-y",
        "-filter_threads",
        "2",
        *inputs,
        "-an",
    ]
    prim, trc, matrix = "bt709", "bt709", "bt709"
    for key, val in zip((extra or [])[::2], (extra or [])[1::2]):
        if key == "-color_primaries":
            prim = val
        if key == "-color_trc":
            trc = val
        if key == "-colorspace":
            matrix = val
    color = f"setparams=color_primaries={prim}:color_trc={trc}:colorspace={matrix}"
    cmd += ["-vf", filters + "," + color if filters else color]
    cmd += [
        "-c:v",
        "ffv1",
        "-threads",
        "2",
        "-pix_fmt",
        pix,
        "-fflags",
        "+bitexact",
        "-flags:v",
        "+bitexact",
        "-color_primaries",
        "bt709",
        "-color_trc",
        "bt709",
        "-colorspace",
        "bt709",
        "-color_range",
        "tv",
        "-chroma_sample_location",
        "left",
    ]
    cmd += extra or []
    cmd += [str(out)]
    subprocess.run(cmd, check=True)
    probe = json.loads(
        subprocess.check_output(
            [
                A.ffprobe,
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_streams",
                "-show_frames",
                "-show_entries",
                "frame=best_effort_timestamp_time,pkt_duration_time:stream=width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,chroma_location,avg_frame_rate,sample_aspect_ratio:stream_side_data",
                "-of",
                "json",
                str(out),
            ]
        )
    )
    records.append(
        dict(
            id=name,
            path=str(out.relative_to(R)),
            sha256=sha(out),
            bytes=out.stat().st_size,
            command=cmd,
            source=source,
            tags=tags or [],
            expected_policy=policy,
            probe=probe,
        )
    )
    return out


specs = [
    ("motion24", "testsrc2=size=640x360:rate=24:duration=2", None, ["high_motion"]),
    ("motion60", "testsrc2=size=640x360:rate=60:duration=2", None, ["60fps"]),
    (
        "motion23976",
        "testsrc2=size=640x360:rate=24000/1001:duration=2",
        None,
        ["fractional_cadence"],
    ),
    (
        "gradient",
        "nullsrc=size=640x360:rate=24:duration=2",
        "format=yuv420p10le,geq=lum='64+876*X/W':cb=512:cr=512",
        ["gradient", "10bit"],
    ),
    (
        "dark_gradient",
        "nullsrc=size=640x360:rate=24:duration=2",
        "format=yuv420p10le,geq=lum='64+128*X/W':cb=512:cr=512",
        ["dark", "banding"],
    ),
    (
        "grain",
        "testsrc2=size=640x360:rate=24:duration=2",
        "noise=alls=12:allf=t+u:all_seed=531",
        ["synthetic_grain"],
    ),
    (
        "line_art",
        "color=c=white:size=640x360:rate=24:duration=2",
        "drawgrid=width=37:height=29:thickness=2:color=black,drawbox=x=200:y=100:w=160:h=160:color=red:t=3",
        ["synthetic_line_art", "static"],
    ),
    (
        "screen_text",
        "color=c=0x182034:size=640x360:rate=24:duration=2",
        "drawtext=text='BetterVMAF 0123456789':fontsize=28:fontcolor=white:x=12:y=30,drawgrid=width=80:height=60:thickness=1:color=gray",
        ["screen_text"],
    ),
]
for name, src, filt, tags in specs:
    make(name, ["-f", "lavfi", "-i", src], filt, tags=tags)
rights = [
    dict(
        id="synthetic",
        license="MIT (repository LICENSE)",
        attribution="BetterVMAF contributors",
        source_url="scripts/validation/generate_corpus.py",
        description="Procedural FFmpeg scenes; no third-party media inputs.",
    )
]
if not A.synthetic_only:
    media = R / "media"
    pinned = json.loads(
        (
            pathlib.Path(__file__).resolve().parents[2]
            / "tests/fixtures/corpus-sources.json"
        ).read_text()
    )["archives"]
    for item in pinned:
        if sha(media / item["filename"]) != item["sha256"]:
            raise ValueError(f"Archive checksum mismatch: {item['filename']}")
    for archive in ["bbb.zip", "tears.zip"]:
        with zipfile.ZipFile(media / archive) as z:
            for member in z.infolist():
                if not member.is_dir() and pathlib.Path(member.filename).suffix in [
                    ".mp4",
                    ".m4v",
                ]:
                    target = media / pathlib.Path(member.filename).name
                    if not target.exists():
                        target.write_bytes(z.read(member))
    for item in pinned:
        if sha(media / item["extracted_filename"]) != item["extracted_sha256"]:
            raise ValueError(
                f"Extracted source checksum mismatch: {item['extracted_filename']}"
            )
    sources = [
        (
            "bbb",
            media / "BigBuckBunny_640x360.m4v",
            [35, 60, 180, 250],
            "https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_640x360.m4v.zip",
            "https://peach.blender.org/about/",
            "(c) 2008 Blender Foundation / www.bigbuckbunny.org",
        ),
        (
            "tears",
            media / "tears-of-steel_teaser.mp4",
            [0, 2, 16, 22],
            "https://download.blender.org/demo/movies/tears-of-steel_teaser.mp4.zip",
            "https://mango.blender.org/sharing/",
            "(CC) Blender Foundation | mango.blender.org",
        ),
    ]
    for src, p, starts, url, license_url, credit in sources:
        rights.append(
            dict(
                id=src,
                source_url=url,
                license_url=license_url,
                license="CC-BY-3.0",
                attribution=credit,
                sha256=sha(p),
                archive_sha256=sha(
                    media / ("bbb.zip" if src == "bbb" else "tears.zip")
                ),
                changes="Audio removed; two-second excerpts scaled to 640-wide, original encoded aspect preserved with explicit square-pixel assumption, converted to FFV1 10-bit BT.709 limited SDR assumption. Teaser is already compressed.",
            )
        )
        for i, start in enumerate(starts):
            make(
                f"{src}_{i + 1}",
                ["-ss", str(start), "-i", str(p), "-t", "2"],
                "scale=640:-2,setsar=1",
                source=src,
                tags=[
                    "animation" if src == "bbb" else "live_action",
                    "heldout" if i == 3 else "development",
                ],
            )
base = O / "motion24.mkv"
inp = ["-i", str(base)]
variations = [
    ("identity", None, [], "valid"),
    ("sharpen", "unsharp=5:5:1.5", [], "valid"),
    ("oversharpen", "unsharp=7:7:3", [], "valid"),
    ("contrast", "eq=contrast=1.15", [], "valid"),
    ("gamma", "eq=gamma=1.15", [], "valid"),
    ("denoise", "hqdn3d=8:8:8:8", [], "valid"),
    ("chroma_blur", "boxblur=0:0:8:2", [], "valid"),
    ("desaturate", "lutyuv=u=512:v=512", [], "valid"),
    ("hue", "hue=h=60", [], "valid"),
    ("uv_corrupt", "lutyuv=u=800:v=200", [], "valid"),
    ("drop_one", "select='not(eq(n,24))',setpts=N/24/TB", [], "refuse_correspondence"),
    (
        "shift_one",
        "trim=start_frame=1,setpts=PTS-STARTPTS",
        [],
        "refuse_unequal_duration",
    ),
    (
        "short_encode",
        "trim=end_frame=24,setpts=PTS-STARTPTS",
        [],
        "refuse_unequal_duration_both_directions",
    ),
    (
        "freeze",
        "trim=end_frame=24,tpad=stop_mode=clone:stop_duration=1",
        [],
        "refuse_unexplained_freeze",
    ),
    (
        "repeat_one",
        "loop=loop=1:size=1:start=24,setpts=N/24/TB",
        [],
        "refuse_correspondence",
    ),
    (
        "vfr",
        "setpts='if(lt(N,24),N/24/TB,(1+(N-24)/12)/TB)'",
        ["-fps_mode", "vfr"],
        "refuse_cadence_mismatch",
    ),
    ("24_to_30", "fps=30", [], "refuse_cadence_mismatch"),
    ("resize", "scale=320:180", [], "explicit_upscale_policy"),
    ("crop_shift", "crop=620:340:20:20,scale=640:360", [], "refuse_unexplained_crop"),
    ("non_square", "setsar=4/3", [], "refuse_aspect"),
    (
        "full_range",
        "scale=in_range=tv:out_range=pc",
        ["-color_range", "pc"],
        "explicit_range_conversion",
    ),
    (
        "missing_metadata",
        None,
        [
            "-color_primaries",
            "unknown",
            "-color_trc",
            "unknown",
            "-colorspace",
            "unknown",
        ],
        "explicit_assumption_or_refuse",
    ),
    (
        "pq_boundary",
        None,
        [
            "-color_primaries",
            "bt2020",
            "-color_trc",
            "smpte2084",
            "-colorspace",
            "bt2020nc",
        ],
        "refuse_hdr",
    ),
    (
        "hlg_boundary",
        None,
        [
            "-color_primaries",
            "bt2020",
            "-color_trc",
            "arib-std-b67",
            "-colorspace",
            "bt2020nc",
        ],
        "refuse_hdr",
    ),
    (
        "interlaced",
        "tinterlace=mode=interleave_top",
        ["-flags:v", "+ildct"],
        "refuse_interlace",
    ),
]
for name, filt, extra, policy in variations:
    make(name, inp, filt, extra, source="motion24", policy=policy)
for name, filt in [
    ("band_8bit", "format=yuv420p"),
    ("band_dither", "zscale=dither=error_diffusion,format=yuv420p"),
]:
    make(
        name,
        ["-i", str(O / "dark_gradient.mkv")],
        filt,
        source="dark_gradient",
        pix="yuv420p",
    )
for family, expr in [
    ("brief", "eq(n,13)"),
    ("periodic", "eq(mod(n,12),5)"),
    ("sustained", "between(n,24,35)"),
]:
    make(
        "damage_" + family,
        inp,
        f"drawbox=color=black:t=fill:enable='{expr}'",
        source="motion24",
        tags=[family],
    )
for codec, encoder, opts in [
    ("avc", "libx264", ["-preset", "medium"]),
    (
        "hevc",
        "libx265",
        ["-preset", "fast", "-x265-params", "pools=2:frame-threads=2:log-level=error"],
    ),
    ("av1", "libsvtav1", ["-preset", "10", "-svtav1-params", "lp=2"]),
]:
    for q in [18, 30, 42]:
        make(
            f"{codec}_q{q}",
            inp,
            None,
            ["-c:v", encoder, *opts, "-crf", str(q)],
            source="motion24",
            pix="yuv420p",
        )
make(
    "sharpen_recompress",
    inp,
    "unsharp=5:5:1.5",
    ["-c:v", "libx264", "-crf", "30", "-preset", "medium"],
    source="motion24",
    pix="yuv420p",
)
# A rotation tag is MOV display-matrix side data, not a pixel rotation.
rot = O / "rotated.mov"
cmd = [
    A.ffmpeg,
    "-v",
    "error",
    "-y",
    "-display_rotation",
    "90",
    "-i",
    str(O / "avc_q18.mkv"),
    "-c",
    "copy",
    str(rot),
]
subprocess.run(cmd, check=True)
records.append(
    dict(
        id="rotated",
        path=str(rot.relative_to(R)),
        sha256=sha(rot),
        command=cmd,
        source="motion24",
        expected_policy="explicit_rotation_policy",
    )
)


# Containers may differ; decoded lossless identity must be exact.
def framehash(p):
    return subprocess.check_output(
        [A.ffmpeg, "-v", "error", "-i", str(p), "-an", "-f", "framemd5", "-"]
    ).decode()


assert framehash(base) == framehash(O / "identity.mkv")
manifest = dict(
    schema=1,
    seed=531,
    ffmpeg=subprocess.check_output([A.ffmpeg, "-version"]).decode(),
    rights=rights,
    records=records,
    checks={"decoded_identity_exact": True},
    boundary_note="PQ/HLG metadata fixtures intentionally retag SDR sample codes: validity tests only, not photometric HDR sources. HDR experiment generates true encoded PQ/HLG separately.",
)
(O / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(
    json.dumps(
        {
            "scenes": len(specs) + (0 if A.synthetic_only else 8),
            "artifacts": len(records),
            "manifest": str(O / "manifest.json"),
        }
    )
)
