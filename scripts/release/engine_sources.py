#!/usr/bin/env python3
"""Stage and verify the release assets for the pinned FFmpeg helpers."""

import argparse
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from release import ROOT, checksum


def verify_files(directory, expected):
    for name, digest in expected.items():
        path = directory / name
        if checksum(path) != f"{digest}  {name}\n":
            raise ValueError(f"FFmpeg source distribution checksum mismatch for {name}")


def source_lock():
    lock = json.loads((ROOT / "Config/EngineSources.json").read_text())
    verify_files(ROOT / "VMAF/Resources", lock["helpers"])
    return lock


def verify_release_assets(release, expected):
    if not release["immutable"] or release["draft"] or release["prerelease"]:
        raise ValueError("FFmpeg source assets must come from an immutable published release")
    digests = {asset["name"]: asset.get("digest") for asset in release["assets"]
               if asset["state"] == "uploaded"}
    for name, digest in expected.items():
        if digests.get(name) != f"sha256:{digest}":
            raise ValueError(f"Missing or incorrect published FFmpeg source asset: {name}")


def verify_origin():
    lock = source_lock()
    endpoint = f"repos/{lock['repository']}/releases/tags/{lock['tag']}"
    result = subprocess.run(["gh", "api", endpoint], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"Cannot inspect pinned FFmpeg source release: {result.stderr.strip()}")
    verify_release_assets(json.loads(result.stdout), lock["assets"])
    return lock


def fetch_sources(directory):
    lock = source_lock()
    url = f"https://github.com/{lock['repository']}/releases/download/{lock['tag']}"
    with TemporaryDirectory(dir=directory) as scratch:
        scratch = Path(scratch)
        for name in lock["assets"]:
            subprocess.run(
                ["curl", "--fail", "--silent", "--show-error", "--location", "--retry", "2",
                 "--max-time", "300", "--output", str(scratch / name), f"{url}/{name}"],
                check=True,
            )
        verify_files(scratch, lock["assets"])
        for name in lock["assets"]:
            (scratch / name).replace(directory / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ["fetch", "verify-files"]:
        commands.add_parser(command).add_argument("directory", type=Path)
    published = commands.add_parser("verify-published")
    published.add_argument("releases", type=Path)
    published.add_argument("tag")
    args = parser.parse_args()

    if args.command == "fetch":
        fetch_sources(args.directory)
    elif args.command == "verify-files":
        verify_files(args.directory, source_lock()["assets"])
    else:
        pages = json.loads(args.releases.read_text())
        record = next((item for page in pages for item in page if item["tag_name"] == args.tag), None)
        if record is None:
            raise ValueError(f"No release record for {args.tag}")
        verify_release_assets(record, source_lock()["assets"])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"FFmpeg source verification failed: {error}") from error
