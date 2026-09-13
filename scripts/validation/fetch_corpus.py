#!/usr/bin/env python3
"""Acquire only explicitly licensed archives; verify before extraction."""

import argparse, hashlib, json, pathlib, subprocess

P = argparse.ArgumentParser()
P.add_argument("--root", type=pathlib.Path, required=True)
A = P.parse_args()
manifest = (
    pathlib.Path(__file__).resolve().parents[2] / "tests/fixtures/corpus-sources.json"
)
for item in json.loads(manifest.read_text())["archives"]:
    target = A.root / "media" / item["filename"]
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        partial = target.with_suffix(".download")
        subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--retry",
                "2",
                "--output",
                str(partial),
                item["url"],
            ],
            check=True,
        )
        partial.replace(target)
    h = hashlib.sha256()
    with target.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    if h.hexdigest() != item["sha256"]:
        raise SystemExit(f"Checksum mismatch: {target}; refusing this archive")
    print(target.name, "verified")
