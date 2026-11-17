#!/usr/bin/env python3
"""Validate BetterVMAF release metadata and render the canonical Sparkle appcast."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "oliverdougherC/BetterVMAF"
RELEASES = f"https://github.com/{REPOSITORY}/releases"
STABLE_FEED = "https://oliverdougherc.github.io/BetterVMAF/appcast.xml"
BUNDLE_ID = "neurophasia.BetterVMAF"
STABLE_MINIMUM_OS = "15.2"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
VERSION = r"[1-9][0-9]{0,2}\.(?:0|[1-9][0-9]{0,2})\.(?:0|[1-9][0-9]{0,2})"
SIGNATURE = re.compile(rb"edSignature: ([A-Za-z0-9+/]{86}==)\nlength: ([0-9]+)\n-->\n")


def build_number(version):
    if not re.fullmatch(VERSION, version):
        raise ValueError(f"Expected canonical MAJOR.MINOR.PATCH with components below 1000: {version}")
    major, minor, patch = map(int, version.split("."))
    return str(major * 1_000_000 + minor * 1_000 + patch)


def project_version(tag=None):
    source = (ROOT / "Config/Version.xcconfig").read_text()
    version, build = (
        re.findall(rf"^{name}\s*=\s*(\S+)\s*$", source, re.MULTILINE)
        for name in ["MARKETING_VERSION", "CURRENT_PROJECT_VERSION"]
    )
    if len(version) != 1 or len(build) != 1 or build[0] != build_number(version[0]):
        raise ValueError("Config/Version.xcconfig has inconsistent version and build numbers")
    if tag is not None and tag != f"v{version[0]}":
        raise ValueError(f"Tag {tag} does not match project version {version[0]}")
    return version[0]


def asset_name(version):
    build_number(version)
    return f"Better-VMAF-{version}.dmg"


def stable_archive(version):
    return f"{RELEASES}/download/v{version}/{asset_name(version)}"


def staging_archive(feed, version):
    parsed = urlsplit(feed)
    if (parsed.scheme, parsed.hostname, parsed.path) != ("http", "localhost", "/appcast.xml"):
        raise ValueError("Staging feed must be http://localhost:<port>/appcast.xml")
    if not parsed.port or parsed.netloc != f"localhost:{parsed.port}" or parsed.query or parsed.fragment:
        raise ValueError("Staging feed must use an explicit localhost port")
    return f"http://localhost:{parsed.port}/{asset_name(version)}"


def check_base64(value, expected_length):
    if len(base64.b64decode(value, validate=True)) != expected_length:
        raise ValueError("Invalid Sparkle key or signature length")


def appcast(version, os_minimum, archive_url, archive_length, archive_signature):
    check_base64(archive_signature, 64)
    if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", os_minimum) or archive_length <= 0:
        raise ValueError("Invalid minimum OS or archive length")

    ET.register_namespace("sparkle", SPARKLE)
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Better VMAF"
    ET.SubElement(channel, "link").text = RELEASES
    ET.SubElement(channel, "description").text = "Better VMAF software updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Better VMAF {version}"
    for key, value in [
        ("version", build_number(version)),
        ("shortVersionString", version),
        ("minimumSystemVersion", os_minimum),
    ]:
        ET.SubElement(item, f"{{{SPARKLE}}}{key}").text = value
    ET.SubElement(item, "enclosure", {
        "url": archive_url,
        "length": str(archive_length),
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": archive_signature,
    })
    ET.indent(rss)
    return ET.tostring(rss, encoding="utf-8", xml_declaration=True) + b"\n"


def check_new_tag(tag, pages):
    version = project_version(tag)
    for release in (item for page in pages for item in page):
        previous = release["tag_name"]
        if previous == tag:
            raise ValueError(f"A release already exists for {tag}")
        if release["draft"] or release["prerelease"] or not release["published_at"]:
            continue
        # Include public two-component tags from before this pipeline.
        previous = previous.removeprefix("v")
        if re.fullmatch(r"[1-9][0-9]{0,2}\.(?:0|[1-9][0-9]{0,2})", previous):
            previous += ".0"
        if re.fullmatch(VERSION, previous) and int(build_number(version)) <= int(build_number(previous)):
            raise ValueError(f"{tag} must sort after published release {release['tag_name']}")
    return version


def select_published(pages):
    candidates = [
        release for page in pages for release in page
        if not release["draft"] and not release["prerelease"]
        and release["published_at"] and re.fullmatch(f"v{VERSION}", release["tag_name"])
    ]
    if not candidates:
        raise ValueError("No published stable releases with a versioned tag")
    release = max(candidates, key=lambda item: int(build_number(item["tag_name"][1:])))
    if not release["immutable"]:
        raise ValueError("The latest stable release must be immutable")
    dmg = asset_name(release["tag_name"][1:])
    uploaded = {asset["name"] for asset in release["assets"] if asset["state"] == "uploaded"}
    if not {dmg, f"{dmg}.sha256", "appcast.xml"} <= uploaded:
        raise ValueError("The latest stable release is missing completed assets")
    return release["tag_name"]


def check_bundle(app, version, mode, feed, key):
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    expected = {
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build_number(version),
        "CFBundleIdentifier": BUNDLE_ID + (".Staging" if mode == "staging" else ""),
        "SUFeedURL": feed,
        "SUPublicEDKey": key,
        "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SUEnableInstallerLauncherService": True,
        "SUSignedFeedFailureExpirationInterval": 0,
    }
    if mode == "production" and ("NSAppTransportSecurity" in info or "SUEnableDownloaderService" in info):
        raise ValueError("Unexpected network override in production bundle")
    for name, value in expected.items():
        if info.get(name) != value:
            raise ValueError(f"Packaged Info.plist has unexpected {name}")
    minimum_os = info["LSMinimumSystemVersion"]
    # A feed with only the latest release must keep the original OS floor.
    if mode == "production" and minimum_os != STABLE_MINIMUM_OS:
        raise ValueError(f"The single-item stable feed requires macOS {STABLE_MINIMUM_OS}; "
                         "retain signed compatible releases before changing the minimum")
    return minimum_os


def app_entitlements(mode):
    bundle_id = BUNDLE_ID + (".Staging" if mode == "staging" else "")
    source = (ROOT / "VMAF/VMAF.entitlements").read_bytes()
    return plistlib.loads(source.replace(b"$(PRODUCT_BUNDLE_IDENTIFIER)", bundle_id.encode("ascii")))


def check_entitlements(app, mode):
    actual = subprocess.check_output(["codesign", "--display", "--xml", "--entitlements", "-", str(app)])
    if plistlib.loads(actual) != app_entitlements(mode):
        raise ValueError("Packaged app signature has unexpected entitlements")


def verify_signature(public_key, path, signature):
    subprocess.run(
        ["xcrun", "swift", str(ROOT / "scripts/release/verify-ed25519.swift"),
         public_key, str(path), signature], check=True,
    )


def verify_appcast(path, dmg, version, archive_url, public_key):
    if path.stat().st_size > 16_384:
        raise ValueError("Unexpected appcast size")
    content, separator, trailer = path.read_bytes().rpartition(b"<!-- sparkle-signatures:\n")
    match = SIGNATURE.fullmatch(trailer)
    if not separator or not match or int(match[2]) != len(content):
        raise ValueError("Invalid Sparkle appcast signature block")
    # Sparkle signs the XML bytes before its trailing comment. Verify these bytes
    # before parsing and accept only the feed our renderer could have produced.
    with TemporaryDirectory() as scratch:
        unsigned_feed = Path(scratch) / "appcast.xml"
        unsigned_feed.write_bytes(content)
        verify_signature(public_key, unsigned_feed, match[1].decode("ascii"))
    item = ET.fromstring(content).find("./channel/item")
    if item is None:
        raise ValueError("Missing Sparkle item")
    os_minimum = item.findtext(f"{{{SPARKLE}}}minimumSystemVersion", "")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing Sparkle enclosure")
    signature = enclosure.attrib[f"{{{SPARKLE}}}edSignature"]
    expected = appcast(version, os_minimum, archive_url, dmg.stat().st_size, signature)
    if content != expected:
        raise ValueError("Appcast differs from the validated release metadata")
    verify_signature(public_key, dmg, signature)
    return os_minimum


def checksum(dmg):
    digest = hashlib.sha256()
    with dmg.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return f"{digest.hexdigest()}  {dmg.name}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=[
        "version", "build-number", "asset-name", "stable-feed", "staging-archive",
        "select-published", "check-new-tag", "check-bundle", "write-entitlements", "check-entitlements", "render-feed", "verify-feed",
        "checksum", "verify-checksum",
    ])
    parser.add_argument("args", nargs="*")
    parsed = parser.parse_args()
    command, args = parsed.command, parsed.args
    if command == "version":
        print(project_version(*args))
    elif command == "build-number":
        print(build_number(*args))
    elif command == "asset-name":
        print(asset_name(*args))
    elif command == "stable-feed":
        print(STABLE_FEED)
    elif command == "staging-archive":
        print(staging_archive(*args))
    elif command == "select-published":
        print(select_published(json.loads(Path(args[0]).read_text())))
    elif command == "check-new-tag":
        print(check_new_tag(args[0], json.loads(Path(args[1]).read_text())))
    elif command == "check-bundle":
        app, version, mode = args
        feed = os.environ.get("SPARKLE_FEED_URL", "")
        key = os.environ.get("SPARKLE_PUBLIC_KEY", "")
        if mode == "production" and feed != STABLE_FEED:
            raise ValueError("Unexpected production feed URL")
        if mode == "staging":
            staging_archive(feed, version)
        if mode != "dry-run":
            check_base64(key, 32)
        print(check_bundle(Path(app), version, mode, feed, key))
    elif command == "write-entitlements":
        path, mode = args
        Path(path).write_bytes(plistlib.dumps(app_entitlements(mode)))
    elif command == "check-entitlements":
        path, mode = args
        check_entitlements(Path(path), mode)
    elif command in {"render-feed", "verify-feed"}:
        if command == "render-feed":
            path, dmg, version, archive_url, minimum_os, signature = args
        else:
            path, dmg, version, archive_url = args
        dmg = Path(dmg)
        if dmg.name != asset_name(version):
            raise ValueError("Unexpected DMG asset name")
        if archive_url == "stable":
            archive_url = stable_archive(version)
        if command == "render-feed":
            Path(path).write_bytes(appcast(version, minimum_os, archive_url, dmg.stat().st_size, signature))
        else:
            print(verify_appcast(Path(path), dmg, version, archive_url, os.environ["SPARKLE_PUBLIC_KEY"]))
    elif command == "checksum":
        print(checksum(Path(args[0])), end="")
    else:
        dmg = Path(args[0])
        if Path(f"{dmg}.sha256").read_text() != checksum(dmg):
            raise ValueError("Release DMG checksum mismatch")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, ET.ParseError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Release validation failed: {error}") from error
