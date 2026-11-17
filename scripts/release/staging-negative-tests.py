#!/usr/bin/env python3
"""Exercise real EdDSA checks against a staging package; never modify its files."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import release

package = Path(sys.argv[1])
version = '1.4.1'
key = os.environ['SPARKLE_PUBLIC_KEY']
url = release.staging_archive(os.environ['SPARKLE_FEED_URL'], version)
with TemporaryDirectory() as scratch:
    scratch = Path(scratch)
    dmg = scratch / release.asset_name(version)
    feed = scratch / 'appcast.xml'
    shutil.copyfile(package / dmg.name, dmg)
    pristine = (package / feed.name).read_bytes()
    feed.write_bytes(pristine)
    release.verify_appcast(feed, dmg, version, url, key)
    for case in ('edited feed', 'malformed feed', 'edited archive', 'wrong identity'):
        feed.write_bytes(pristine)
        if case == 'edited feed':
            feed.write_bytes(pristine.replace(b'Better VMAF', b'Other Video', 1))
        elif case == 'malformed feed':
            feed.write_bytes(b'<rss>')
        elif case == 'edited archive':
            with dmg.open('r+b') as target:
                first = target.read(1)
                target.seek(0)
                target.write(bytes([first[0] ^ 1]))
        try:
            release.verify_appcast(feed, dmg, version, url,
                                   'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' if case == 'wrong identity' else key)
        except (ValueError, subprocess.CalledProcessError):
            print(f'Correctly rejected: {case}')
        else:
            raise SystemExit(f'FAILED to reject: {case}')
        if case == 'edited archive':
            shutil.copyfile(package / dmg.name, dmg)
