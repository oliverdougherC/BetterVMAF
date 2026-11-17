import base64
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import release

SIGNATURE = base64.b64encode(bytes(64)).decode("ascii")
VERSION = "1.4.0"


def published(tag, **changes):
    dmg = f"Better-VMAF-{tag.removeprefix('v')}.dmg"
    record = {
        "tag_name": tag,
        "draft": False,
        "prerelease": False,
        "published_at": "2026-11-17T00:00:00Z",
        "immutable": True,
        "assets": [{"name": name, "state": "uploaded"} for name in [dmg, dmg + ".sha256", "appcast.xml"]],
    }
    return record | changes


class VersionTests(unittest.TestCase):
    def test_expected_tag_and_build(self):
        version = release.project_version()
        self.assertEqual(release.project_version(f"v{version}"), version)
        for bad in [version, f"v{version}-rc.1", "v0.0.0", "v99.99.99"]:
            with self.subTest(tag=bad), self.assertRaises(ValueError):
                release.project_version(bad)
        self.assertEqual(release.build_number("1.4.0"), "1004000")

    def test_build_order_matches_version_order(self):
        versions = ["1.3.999", "1.4.0", "1.4.2", "1.4.10", "1.999.999", "2.0.0"]
        builds = [int(release.build_number(version)) for version in versions]
        self.assertEqual(builds, sorted(set(builds)))
        for bad in ["1.04.0", "1.1000.0", "1.4", "1.4.0+build", "1.4.0-rc.1"]:
            with self.subTest(version=bad), self.assertRaises(ValueError):
                release.build_number(bad)

    def test_draft_cannot_be_overwritten_and_new_tag_must_advance(self):
        version = release.project_version()
        tag = f"v{version}"
        self.assertEqual(release.check_new_tag(tag, [[published("1.4", draft=True)]]), version)
        for record in [published(tag, draft=True), published(version), published("v999.999.999")]:
            with self.subTest(record=record), self.assertRaises(ValueError):
                release.check_new_tag(tag, [[record]])


class PublicationTests(unittest.TestCase):
    def test_selects_numerically_latest_stable_across_pages(self):
        pages = [
            [published("v1.4.2"), published("v9.0.0", draft=True), published("v8.0.0", prerelease=True)],
            [published("1.3"), published("v1.4.10"), published("v2.0.0-rc.1")],
        ]
        self.assertEqual(release.select_published(pages), "v1.4.10")

    def test_blocks_incomplete_or_mutable_release(self):
        for newest in [
            published("v2.0.0", immutable=False),
            published("v2.0.0", assets=[]),
            published("v2.0.0", assets=[{"name": "appcast.xml", "state": "new"}]),
        ]:
            with self.subTest(newest=newest), self.assertRaises(ValueError):
                release.select_published([[published("v1.4.0"), newest]])

    def test_staging_only_uses_localhost(self):
        url = "http://localhost:8000/appcast.xml"
        self.assertEqual(release.staging_archive(url, VERSION), "http://localhost:8000/Better-VMAF-1.4.0.dmg")
        for bad in [release.STABLE_FEED, "http://localhost:8000@evil.test/appcast.xml", url + "?x=y"]:
            with self.subTest(url=bad), self.assertRaises(ValueError):
                release.staging_archive(bad, VERSION)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        scratch = TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.dmg = Path(scratch.name) / release.asset_name(VERSION)
        self.dmg.write_bytes(b"test archive")
        self.feed = Path(scratch.name) / "appcast.xml"
        self.url = release.stable_archive(VERSION)
        self.contents = release.appcast(VERSION, "15.2", self.url, self.dmg.stat().st_size, SIGNATURE)

    def write_signed_feed(self, data):
        trailer = f"<!-- sparkle-signatures:\nedSignature: {SIGNATURE}\nlength: {len(data)}\n-->\n"
        self.feed.write_bytes(data + trailer.encode("ascii"))

    def verify(self):
        return release.verify_appcast(self.feed, self.dmg, VERSION, self.url, "test public key")

    @patch("release.verify_signature")
    def test_checks_feed_and_archive_and_uses_bundle_version(self, verify):
        self.write_signed_feed(self.contents)
        self.assertEqual(self.verify(), "15.2")
        self.assertIn(b"<sparkle:version>1004000</sparkle:version>", self.contents)
        self.assertEqual(verify.call_count, 2)
        self.assertEqual(verify.call_args.args[1:], (self.dmg, SIGNATURE))

    @patch("release.verify_signature")
    def test_rejects_wrong_urls_versions_lengths_or_extra_items(self, verify):
        for data in [
            self.contents.replace(self.url.encode(), b"https://example.test/update.dmg"),
            self.contents.replace(b"1004000", b"1003999"),
            self.contents.replace(b'length="12"', b'length="13"'),
            self.contents.replace(b"</item>", b"</item><item/>"),
        ]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.write_signed_feed(data)
                self.verify()

    @patch("release.verify_signature")
    def test_missing_or_malformed_signatures_are_rejected_before_parsing(self, verify):
        self.feed.write_bytes(self.contents)
        with self.assertRaises(ValueError):
            self.verify()
        self.write_signed_feed(self.contents)
        self.feed.write_bytes(self.feed.read_bytes().replace(b"length: ", b"x: "))
        with self.assertRaises(ValueError):
            self.verify()
        verify.assert_not_called()

    @unittest.skipUnless(sys.platform == "darwin", "Uses the macOS CryptoKit verifier")
    def test_real_signature_rejects_modified_bytes(self):
        # RFC 8032 section 7.1, test 2. These are published test vectors.
        public_key = base64.b64encode(bytes.fromhex(
            "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
        )).decode("ascii")
        signature = base64.b64encode(bytes.fromhex(
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
            "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
        )).decode("ascii")
        self.dmg.write_bytes(b"\x72")
        release.verify_signature(public_key, self.dmg, signature)
        self.dmg.write_bytes(b"\x73")
        with self.assertRaises(subprocess.CalledProcessError):
            release.verify_signature(public_key, self.dmg, signature)

    def test_checksum_changes_when_archive_is_modified(self):
        before = release.checksum(self.dmg)
        self.dmg.write_bytes(b"bad archive!")
        self.assertNotEqual(before, release.checksum(self.dmg))


if __name__ == "__main__":
    unittest.main()
