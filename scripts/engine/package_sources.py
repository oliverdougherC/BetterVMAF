#!/usr/bin/env python3
"""Create the corresponding-source companion archive for distributing this engine."""
import argparse
import os
import hashlib
import json
from pathlib import Path
import zipfile
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source-archives', type=Path, default=Path.home() / 'Library/Caches/BetterVMAF-engine/source-archives')
ap.add_argument('--engine', type=Path, default=ROOT / 'VMAF/Resources/engine')
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--fetch-missing', action='store_true', help='Fetch pinned upstream source trees when archive cache is absent')
args = ap.parse_args()
manifest = json.loads((args.engine / 'manifest.json').read_text())
archives = []
for name, source in manifest['sources'].items():
    path = args.source_archives / source['sourceArchive']
    if not path.exists() and args.fetch_missing:
        args.source_archives.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='bettervmaf-source-') as td:
            def git(*command):
                subprocess.run(['git', '-C', td, *command], check=True, env={key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'USER', 'LOGNAME') if key in os.environ})
            git('init')
            git('fetch', '--depth=1', source['repository'], source['revision'])
            git('archive', '--format=tar', '--prefix=' + name + '/', '-o', str(path.resolve()), source['revision'])
    if hashlib.sha256(path.read_bytes()).hexdigest() != source['sourceArchiveSHA256']:
        raise SystemExit(f'Source archive checksum mismatch: {path}')
    archives.append(path)
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
    for archive in archives:
        bundle.write(archive, 'sources/' + archive.name)
    for script in Path(__file__).parent.glob('*.py'):
        bundle.write(script, 'scripts/engine/' + script.name)
    bundle.write(args.engine / 'manifest.json', 'VMAF/Resources/engine/manifest.json')
    for notice in (args.engine / 'licenses').glob('*'):
        bundle.write(notice, 'VMAF/Resources/engine/licenses/' + notice.name)
    bundle.write(ROOT / 'docs/ENGINE.md', 'docs/ENGINE.md')
    bundle.writestr('README.txt', 'BetterVMAF engine corresponding source\n\nEach sources/*.tar is the complete unmodified pinned upstream Git tree. SHA-256 hashes and revisions are in VMAF/Resources/engine/manifest.json. Extract source trees to a scratch build directory to inspect or modify. The scripts/engine/build.py recipe records every configure and build option and can fetch the same revisions. See docs/ENGINE.md for tools, licensing, and rebuild instructions. No proprietary external library is needed to build these command-line programs.\n')
print(f'{args.output}: {args.output.stat().st_size} bytes; SHA-256 {hashlib.sha256(args.output.read_bytes()).hexdigest()}')
