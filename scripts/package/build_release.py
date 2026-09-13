#!/usr/bin/env python3
"""Build, validate and package a local ad-hoc signed arm64 BetterVMAF release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BUILD_ENV = {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'USER', 'LOGNAME', 'DEVELOPER_DIR') if key in os.environ}

def run(command, **kwargs):
    kwargs.setdefault('env', BUILD_ENV)
    return subprocess.run([str(x) for x in command], check=True, **kwargs)

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--app', type=Path, help='Use this already built app instead of running xcodebuild')
    ap.add_argument('--output', type=Path, default=ROOT / 'Better-VMAF.dmg')
    ap.add_argument('--source-archives', type=Path, default=Path.home() / 'Library/Caches/BetterVMAF-engine/source-archives')
    ap.add_argument('--evidence', type=Path, help='Optional durable packaging evidence JSON')
    args = ap.parse_args()
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, env=BUILD_ENV, text=True).strip()
    with tempfile.TemporaryDirectory(prefix='bettervmaf-package-') as td:
        work = Path(td)
        if args.app:
            built_app = args.app.resolve()
        else:
            build = work / 'Build'
            run(['xcodebuild', '-project', ROOT / 'VMAF.xcodeproj', '-scheme', 'VMAF', '-configuration', 'Release', '-destination', 'generic/platform=macOS', '-derivedDataPath', work / 'DerivedData', 'CONFIGURATION_BUILD_DIR=' + str(build), 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'BETTERVMAF_SOURCE_COMMIT=' + source_commit, 'CODE_SIGNING_ALLOWED=NO', 'build'], cwd=ROOT)
            built_app = build / 'Better VMAF.app'
        if not built_app.is_dir():
            raise RuntimeError(f'App missing: {built_app}')
        staging = work / 'staging'
        staging.mkdir()
        app = staging / 'Better VMAF.app'
        run(['ditto', built_app, app])
        engine = app / 'Contents/Resources/engine'
        # Validate the replacement before removing legacy packaged resources.
        run([sys.executable, ROOT / 'scripts/engine/verify.py', '--engine', engine, '--report', work / 'engine-before-sign.json'], stdout=subprocess.DEVNULL)
        legacy = app / 'Contents/Resources/ffmpeg'
        if legacy.exists():
            legacy.unlink()
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        version = info['CFBundleShortVersionString']
        build_number = info['CFBundleVersion']
        if info.get('BetterVMAFSourceCommit') != source_commit:
            raise RuntimeError('App source revision is missing or differs from this checkout. Rebuild with BETTERVMAF_SOURCE_COMMIT=' + source_commit)
        executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
        arch = subprocess.check_output(['lipo', '-archs', executable], text=True, env=BUILD_ENV).strip()
        if arch != 'arm64':
            raise RuntimeError(f'Expected arm64 app executable, found {arch}')
        manifest = json.loads((engine / 'manifest.json').read_text())
        for helper in ['ffmpeg', 'ffprobe', 'vmaf']:
            # These pinned artifacts already have valid ad-hoc signatures. Re-signing
            # on a different OS can change bytes and invalidate their source manifest.
            run(['codesign', '--verify', '--strict', engine / helper])
        run(['codesign', '--force', '--sign', '-', '--entitlements', ROOT / 'VMAF/VMAF.entitlements', app])
        run(['codesign', '--verify', '--deep', '--strict', app])
        entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', app], env=BUILD_ENV, stderr=subprocess.DEVNULL))
        assert entitlements.get('com.apple.security.app-sandbox') is True
        assert entitlements.get('com.apple.security.files.user-selected.read-write') is True
        run([sys.executable, ROOT / 'scripts/engine/verify.py', '--engine', engine, '--report', work / 'engine-after-sign.json'], stdout=subprocess.DEVNULL)
        sources = staging / 'BetterVMAF-engine-source.zip'
        run([sys.executable, ROOT / 'scripts/engine/package_sources.py', '--engine', engine, '--source-archives', args.source_archives, '--fetch-missing', '--output', sources])
        (staging / 'Applications').symlink_to('/Applications')
        (staging / 'READ ME.txt').write_text(f'BetterVMAF {version} ({build_number})\n\nNative arm64 macOS; compiler deployment target {manifest["minimumMacOS"]}.\nThis is a local ad-hoc signed build, not Developer ID signed or notarized.\nDrag Better VMAF.app to Applications. The matching FFmpeg/libvmaf/dav1d source and build recipes are in BetterVMAF-engine-source.zip. Dependency notices and checksums are also inside the app at Contents/Resources/engine.\n')
        dmg = work / 'Better-VMAF.dmg'
        run(['hdiutil', 'create', '-volname', f'BetterVMAF {version}', '-srcfolder', staging, '-format', 'UDZO', dmg])
        run(['hdiutil', 'verify', dmg])
        mounted = work / 'mounted'
        mounted.mkdir()
        run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mounted, dmg], stdout=subprocess.DEVNULL)
        try:
            packaged_app = mounted / app.name
            packaged_engine = packaged_app / 'Contents/Resources/engine'
            run(['codesign', '--verify', '--deep', '--strict', packaged_app])
            run([sys.executable, ROOT / 'scripts/engine/verify.py', '--engine', packaged_engine, '--report', work / 'engine-mounted.json'], stdout=subprocess.DEVNULL)
            mounted_info = plistlib.loads((packaged_app / 'Contents/Info.plist').read_bytes())
            assert mounted_info['CFBundleShortVersionString'] == version
            assert mounted_info['CFBundleVersion'] == build_number
            assert mounted_info['BetterVMAFSourceCommit'] == source_commit
            assert not (packaged_app / 'Contents/Resources/ffmpeg').exists()
            assert sha256(mounted / sources.name) == sha256(sources)
        finally:
            run(['hdiutil', 'detach', mounted], stdout=subprocess.DEVNULL)
        evidence = {'schemaVersion': 1, 'version': version, 'buildNumber': build_number, 'architecture': arch, 'engineID': manifest['engineID'], 'engineManifestSHA256': sha256(engine / 'manifest.json'), 'dmgSHA256': sha256(dmg), 'dmgBytes': dmg.stat().st_size, 'sourceArchiveSHA256': sha256(sources), 'sourceArchiveBytes': sources.stat().st_size, 'signing': 'ad-hoc', 'notarized': False, 'checks': ['engine hashes and native smoke before signing', 'pinned helper signatures preserved; app ad-hoc signed', 'deep strict signature verification', 'system-only dependencies and PATH', 'mounted read-only DMG native metric smoke', 'matching version and build metadata', 'source companion included and hash verified', 'legacy Intel binary omitted from package'], 'notTested': ['separate pristine Mac', 'macOS 15.2 execution', 'Gatekeeper approval for public distribution', 'interactive packaged-app comparison/cancellation/export'], 'mountedEngineChecks': json.loads((work / 'engine-mounted.json').read_text())['checks']}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        evidence['appSourceCommit'] = source_commit
        evidence['appExecutableSHA256'] = sha256(executable)
        evidence['sandboxEntitlements'] = entitlements
        evidence['checks'].extend(['embedded application source revision matches checkout', 'sandbox and user-selected read/write entitlements verified'])
        # Publish outputs only after all checks have succeeded.
        shutil.copy2(dmg, args.output)
        sidecar = args.output.with_suffix('.manifest.json')
        sidecar.write_text(json.dumps(evidence, indent=2) + '\n')
        args.output.with_suffix('.sha256').write_text(evidence['dmgSHA256'] + '  ' + args.output.name + '\n')
        if args.evidence:
            args.evidence.parent.mkdir(parents=True, exist_ok=True)
            args.evidence.write_text(json.dumps(evidence, indent=2) + '\n')
        print(f'Validated {args.output} ({version}, build {build_number}); provenance: {sidecar}')

if __name__ == '__main__':
    main()
