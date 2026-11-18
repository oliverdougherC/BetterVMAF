import base64
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import engine_sources
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

    def test_requires_pinned_ffmpeg_source_and_notices_on_published_release(self):
        expected = {"source.zip": "a" * 64, "notices.zip": "b" * 64}
        assets = [{"name": name, "state": "uploaded", "digest": f"sha256:{digest}"}
                  for name, digest in expected.items()]
        engine_sources.verify_release_assets(published("v1.4.0", assets=assets), expected)
        for release_record in [
            published("v1.4.0", assets=assets[:1]),
            published("v1.4.0", assets=[assets[0], assets[1] | {"digest": "sha256:wrong"}]),
            published("v1.4.0", assets=assets, draft=True),
        ]:
            with self.subTest(release=release_record), self.assertRaises(ValueError):
                engine_sources.verify_release_assets(release_record, expected)

    def test_rejects_changed_ffmpeg_source_asset(self):
        source = b"pinned source archive"
        with TemporaryDirectory() as scratch:
            directory = Path(scratch)
            source_path = directory / "source.zip"
            source_path.write_bytes(source)
            expected = {source_path.name: hashlib.sha256(source).hexdigest()}
            engine_sources.verify_files(directory, expected)
            source_path.write_bytes(b"P" + source[1:])
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                engine_sources.verify_files(directory, expected)

    def test_ffmpeg_source_lock_covers_both_bundled_helpers(self):
        lock = engine_sources.source_lock()
        self.assertEqual(set(lock["helpers"]), {"ffmpeg", "ffmpeg.x86_64"})
        self.assertEqual(len(lock["assets"]), 2)

    def test_single_item_production_feed_cannot_raise_the_os_floor(self):
        with TemporaryDirectory() as scratch:
            app = Path(scratch)
            contents = app / "Contents"
            contents.mkdir()
            plist = contents / "Info.plist"
            info = {
                "CFBundleShortVersionString": VERSION,
                "CFBundleVersion": release.build_number(VERSION),
                "CFBundleIdentifier": release.BUNDLE_ID,
                "SUFeedURL": release.STABLE_FEED,
                "SUPublicEDKey": "test public key",
                "SURequireSignedFeed": True,
                "SUVerifyUpdateBeforeExtraction": True,
                "SUEnableInstallerLauncherService": True,
                "SUSignedFeedFailureExpirationInterval": 0,
                "LSMinimumSystemVersion": "15.2",
            }
            plist.write_bytes(plistlib.dumps(info))
            self.assertEqual(release.check_bundle(app, VERSION, "production", release.STABLE_FEED,
                                                  "test public key"), "15.2")
            info["LSMinimumSystemVersion"] = "16.0"
            plist.write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, "retain signed compatible releases"):
                release.check_bundle(app, VERSION, "production", release.STABLE_FEED, "test public key")

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

    def test_real_staging_feed_fixture_and_corruption(self):
        fixture = release.ROOT / 'Fixtures/ReleaseStaging'
        public = (fixture / 'public-key.txt').read_text().strip()
        content = release.signed_feed_content(fixture / 'appcast.xml', public)
        self.assertIn(b'http://localhost:18742/', content)
        self.feed.write_bytes((fixture / 'appcast.xml').read_bytes().replace(b'Better VMAF', b'Other Video', 1))
        with self.assertRaises(subprocess.CalledProcessError):
            release.signed_feed_content(self.feed, public)

    def test_checksum_changes_when_archive_is_modified(self):
        before = release.checksum(self.dmg)
        self.dmg.write_bytes(b"bad archive!")
        self.assertNotEqual(before, release.checksum(self.dmg))


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS codesign")
class DeveloperIDTests(unittest.TestCase):
    def test_verifier_accepts_pinned_developer_id_and_rejects_wrong_team(self):
        script = 'source scripts/release/verify-developer-id.sh; verify_developer_id "$@"'
        helpers = ['VMAF/Resources/ffmpeg', 'VMAF/Resources/ffmpeg.x86_64']
        command = ['bash', '-c', script, 'verify_developer_id']
        subprocess.run([*command, 'KU3N25YGLU', *helpers], cwd=release.ROOT, check=True)
        wrong_team = subprocess.run([*command, 'AAAAAAAAAA', helpers[0]], cwd=release.ROOT,
                                    text=True, capture_output=True)
        self.assertNotEqual(wrong_team.returncode, 0)
        self.assertIn('code failed to satisfy specified code requirement', wrong_team.stderr)


class SigningInputTests(unittest.TestCase):
    def test_missing_credentials_fail_before_build_and_leave_no_package(self):
        names = ['SPARKLE_PUBLIC_KEY', 'SPARKLE_PRIVATE_KEY', 'APPLE_TEAM_ID',
                 'APPLE_CERTIFICATE_P12', 'APPLE_CERTIFICATE_PASSWORD', 'APPLE_NOTARY_KEY',
                 'APPLE_NOTARY_KEY_ID', 'APPLE_NOTARY_ISSUER_ID']
        environment = {k: v for k, v in os.environ.items() if k not in names}
        with TemporaryDirectory() as scratch:
            destination = Path(scratch) / 'package'
            result = subprocess.run(['bash', str(release.ROOT / 'scripts/release/package.sh'),
                                     'production', str(destination), f'v{release.project_version()}'],
                                    env=environment, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            for name in names:
                self.assertIn(f'Missing production signing setting: {name}', result.stderr)
            self.assertNotIn('xcodebuild', result.stdout)
            self.assertFalse(destination.exists())

    def test_credentials_are_removed_from_child_environments(self):
        environment = os.environ | {'SPARKLE_PRIVATE_KEY': 'private-test-sentinel',
                                    'APPLE_CERTIFICATE_PASSWORD': 'password-test-sentinel'}
        script = 'source scripts/release/check-signing-inputs.sh; /usr/bin/env'
        result = subprocess.run(['bash', '-c', script], cwd=release.ROOT, env=environment,
                                text=True, capture_output=True, check=True)
        self.assertNotIn('private-test-sentinel', result.stdout)
        self.assertNotIn('password-test-sentinel', result.stdout)


if __name__ == "__main__":
    unittest.main()
