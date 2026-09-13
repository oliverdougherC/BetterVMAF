#!/usr/bin/env python3
"""Build the pinned arm64 engine; sources and intermediate objects stay outside Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PINS = {
    'ffmpeg': ('https://github.com/FFmpeg/FFmpeg.git', '9047fa1b084f76b1b4d065af2d743df1b40dfb56', '8.1', 'LGPL-2.1-or-later'),
    'vmaf': ('https://github.com/Netflix/vmaf.git', 'f85a853692a8c730d0270cd733c8bb30b5b93b7c', '3.2.0+f85a853', 'BSD-2-Clause-Patent'),
    'dav1d': ('https://code.videolan.org/videolan/dav1d.git', 'b546257f770768b2c88258c533da38b91a06f737', '1.5.3', 'BSD-2-Clause'),
}

def run(args, **kwargs):
    kwargs.setdefault('env', {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'USER', 'LOGNAME', 'DEVELOPER_DIR') if key in os.environ})
    return subprocess.run([str(x) for x in args], check=True, **kwargs)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--cache', type=Path, default=Path.home() / 'Library/Caches/BetterVMAF-engine')
    ap.add_argument('--output', type=Path, default=ROOT / 'VMAF/Resources/engine')
    ap.add_argument('--jobs', type=int, default=min(6, os.cpu_count() or 2))
    ap.add_argument('--stage-only', action='store_true', help='Package an already completed build at --cache')
    args = ap.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        ap.error('This artifact supports native arm64 macOS only; Intel is not shipped.')
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    prefix = cache / 'prefix'
    # Meson test logs serialize their environment: never forward unrelated credentials.
    env = {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'USER', 'LOGNAME', 'DEVELOPER_DIR') if key in os.environ}
    env['LC_ALL'] = 'C'
    env['SDKROOT'] = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True, env=env).strip()
    env['PATH'] = str(cache / 'tools/bin') + os.pathsep + env['PATH']
    env['PKG_CONFIG_LIBDIR'] = str(prefix / 'lib/pkgconfig')
    flags = ['--prefix=' + str(prefix), '--arch=arm64', '--cc=clang', '--enable-libvmaf', '--enable-libdav1d', '--enable-static', '--disable-shared', '--disable-autodetect', '--disable-doc', '--disable-debug', '--disable-ffplay', '--disable-network', '--enable-videotoolbox', '--enable-audiotoolbox', '--enable-zlib', '--pkg-config-flags=--static', '--extra-cflags=-mmacosx-version-min=15.2', '--extra-ldflags=-mmacosx-version-min=15.2', '--extra-libs=-lc++']
    if not args.stage_only:
        if not (cache / 'tools/bin/meson').exists():
            run(['python3', '-m', 'venv', cache / 'tools'])
            run([cache / 'tools/bin/pip', 'install', 'meson==1.10.1', 'ninja==1.13.0'])
        for name, (url, revision, _, _) in PINS.items():
            source = cache / name
            if not source.exists():
                run(['git', 'init', source])
                run(['git', '-C', source, 'remote', 'add', 'origin', url])
                run(['git', '-C', source, 'fetch', '--depth=1', 'origin', revision])
                run(['git', '-C', source, 'checkout', '--detach', revision])
            actual = subprocess.check_output(['git', '-C', source, 'rev-parse', 'HEAD'], text=True, env=env).strip()
            if actual != revision or subprocess.check_output(['git', '-C', source, 'diff', '--name-only'], text=True, env=env).strip():
                raise RuntimeError(f'{source}: expected clean pinned source {revision}; use a fresh cache')
        for name, subdir, options in [('vmaf', 'libvmaf', ['-Denable_tests=true', '-Denable_docs=false', '-Denable_tools=true', '-Dbuilt_in_models=true', '-Dcpp_args=-mmacosx-version-min=15.2']), ('dav1d', '', ['-Denable_tools=false', '-Denable_tests=false'])]:
            build = cache / (name + '-build')
            if not (build / 'build.ninja').exists():
                run(['meson', 'setup', build, cache / name / subdir, '--prefix=' + str(prefix), '--buildtype=release', '--default-library=static', '-Dc_args=-mmacosx-version-min=15.2'] + options, env=env)
            run(['ninja', '-C', build, '-j', args.jobs, 'install'], env=env)
        run(['meson', 'test', '-C', cache / 'vmaf-build', '--print-errorlogs'], env=env)
        run([cache / 'ffmpeg/configure'] + flags, cwd=cache / 'ffmpeg', env=env)
        run(['make', '-j', args.jobs], cwd=cache / 'ffmpeg', env=env)
        run(['make', 'install'], cwd=cache / 'ffmpeg', env=env)
    for name, (_, revision, _, _) in PINS.items():
        actual = subprocess.check_output(['git', '-C', cache / name, 'rev-parse', 'HEAD'], text=True, env=env).strip()
        dirty = subprocess.check_output(['git', '-C', cache / name, 'diff', '--name-only', 'HEAD'], text=True, env=env).strip()
        if actual != revision or dirty:
            raise RuntimeError(f'{name}: refuse to package an unpinned or modified source build')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / 'models').mkdir(exist_ok=True)
    (output / 'licenses').mkdir(exist_ok=True)
    for name in ['ffmpeg', 'ffprobe', 'vmaf']:
        shutil.copy2(prefix / 'bin' / name, output / name)
        run(['strip', '-x', output / name])
        run(['codesign', '--force', '--sign', '-', output / name])
    for folder in ['vmaf_v1.0.16', 'vmaf_v1.0.16_hfr']:
        for model in (cache / 'vmaf/model' / folder).glob('*.json'):
            shutil.copy2(model, output / 'models' / model.name)
    shutil.copy2(cache / 'vmaf/model/vmaf_v0.6.1neg.json', output / 'models/vmaf_v0.6.1neg.json')
    for source, target in [('ffmpeg/COPYING.LGPLv2.1', 'FFmpeg-LGPL-2.1.txt'), ('ffmpeg/LICENSE.md', 'FFmpeg-license-details.md'), ('vmaf/LICENSE', 'libvmaf-BSD-2-Clause-Patent.txt'), ('dav1d/COPYING', 'dav1d-BSD-2-Clause.txt'), ('dav1d/doc/PATENTS', 'dav1d-AOM-PATENTS.txt')]:
        shutil.copy2(cache / source, output / 'licenses' / target)
    notice = ROOT / 'VMAF/Resources/engine/licenses/NOTICE.txt'
    if notice.resolve() != (output / 'licenses/NOTICE.txt').resolve():
        shutil.copy2(notice, output / 'licenses/NOTICE.txt')
    svm_notice = (cache / 'vmaf/libvmaf/src/svm.h').read_text().split('*/', 1)[0].removeprefix('/**').strip()
    (output / 'licenses/libsvm-COPYRIGHT.txt').write_text(svm_notice + '\n')
    sources = {}
    archives = cache / 'source-archives'
    archives.mkdir(exist_ok=True)
    for name, (url, revision, version, license_name) in PINS.items():
        archive = archives / f'{name}-{revision}.tar'
        run(['git', '-C', cache / name, 'archive', '--format=tar', '--prefix=' + name + '/', '-o', archive, revision])
        sources[name] = {'repository': url, 'revision': revision, 'version': version, 'license': license_name, 'sourceArchive': archive.name, 'sourceArchiveSHA256': digest(archive)}
    manifest = {'schemaVersion': 1, 'engineID': 'bettervmaf-arm64-ffmpeg8.1-vmaf-f85a853-dav1d1.5.3', 'architecture': 'arm64', 'minimumMacOS': '15.2', 'sources': sources, 'configureArguments': flags, 'toolchain': {'clang': subprocess.check_output(['clang', '--version'], text=True, env=env).splitlines()[0], 'sdk': env['SDKROOT'], 'meson': '1.10.1', 'ninja': '1.13.0'}, 'capabilities': ['libvmaf-v1', 'xpsnr', 'cambi-full-reference', 'ffprobe-json', 'av1-software-decoding'], 'files': {str(p.relative_to(output)): {'sha256': digest(p), 'bytes': p.stat().st_size} for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'manifest.json'}}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    print(f'Engine staged at {output}. Matching source archives: {archives}')
    print('Run scripts/engine/verify.py before replacing or distributing the old engine.')

if __name__ == '__main__':
    main()
