#!/usr/bin/env python3
"""Verify the shipped tuple on native macOS; no system FFmpeg or downloaded fixtures."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--engine', type=Path, default=ROOT / 'VMAF/Resources/engine')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    engine = args.engine.resolve()
    manifest = json.loads((engine / 'manifest.json').read_text())
    if platform.machine() != 'arm64' or platform.system() != 'Darwin':
        raise RuntimeError('Verification requires native arm64 macOS')
    evidence = {'engineID': manifest['engineID'], 'host': platform.platform(), 'checks': {}, 'commands': []}
    # An empty, system-only environment makes accidental Homebrew runtime use visible.
    env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(Path.home()), 'LC_ALL': 'C'}
    def run(command, cwd=None):
        command = [str(x) for x in command]
        evidence['commands'].append(command)
        p = subprocess.run(command, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        if p.returncode:
            raise RuntimeError(f'{command}: {p.stderr[-8000:]}')
        return p
    for path, entry in manifest['files'].items():
        actual = hashlib.sha256((engine / path).read_bytes()).hexdigest()
        assert actual == entry['sha256'], f'Checksum mismatch {path}'
    evidence['checks']['manifestHashes'] = len(manifest['files'])
    for helper in ['ffmpeg', 'ffprobe', 'vmaf']:
        path = engine / helper
        assert os.access(path, os.X_OK), f'Not executable: {path}'
        assert run(['/usr/bin/lipo', '-archs', path]).stdout.strip() == 'arm64'
        deps = run(['/usr/bin/otool', '-L', path]).stdout.splitlines()[1:]
        assert all(x.strip().startswith(('/usr/lib/', '/System/Library/')) for x in deps), deps
        run(['/usr/bin/codesign', '--verify', '--strict', path])
        evidence['checks'][helper + 'Dependencies'] = [x.strip() for x in deps]
    ff = engine / 'ffmpeg'
    filters = run([ff, '-hide_banner', '-filters']).stdout
    assert all(re.search(r'\b' + name + r'\b', filters) for name in ['libvmaf', 'xpsnr', 'scale', 'showinfo'])
    assert 'libdav1d' in run([ff, '-hide_banner', '-decoders']).stdout
    evidence['checks']['ffmpegVersion'] = run([ff, '-version']).stdout
    version = run([engine / 'vmaf', '--version'])
    evidence['checks']['libvmafVersion'] = (version.stdout + version.stderr).strip()
    with tempfile.TemporaryDirectory(prefix='bettervmaf-native-') as td:
        work = Path(td)
        def ffmpeg(*args):
            return run([ff, '-hide_banner', '-nostdin', '-y', '-threads', '4', *args], cwd=work)
        ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=0.5', '-vf', 'format=yuv420p10le', '-c:v', 'ffv1', 'reference.mkv')
        ffmpeg('-i', 'reference.mkv', '-vf', 'gblur=sigma=0.8:steps=2,lutyuv=u=val+2:v=val-2', '-c:v', 'ffv1', 'distorted.mkv')
        probe = json.loads(run([engine / 'ffprobe', '-v', 'error', '-show_streams', '-of', 'json', work / 'reference.mkv']).stdout)
        assert probe['streams'][0]['pix_fmt'] == 'yuv420p10le'
        ffmpeg('-i', 'reference.mkv', '-pix_fmt', 'yuv420p10le', '-f', 'rawvideo', 'reference.yuv')
        ffmpeg('-i', 'distorted.mkv', '-pix_fmt', 'yuv420p10le', '-f', 'rawvideo', 'distorted.yuv')
        options = 'cambi.enc_width=640:cambi.enc_height=360:cambi.enc_bitdepth=10'
        feature = 'name=cambi:full_ref=true:enc_width=640:enc_height=360:enc_bitdepth=10:src_width=640:src_height=360'
        def quote(value):
            return "'" + value.replace(':', '\\:') + "'"
        def score(model, distorted='distorted.mkv', output='vmaf.json'):
            shutil.copy2(model, work / 'model.json')
            graph = '[1:v][0:v]libvmaf=model=' + quote('path=model.json:' + options) + ':feature=' + quote(feature) + ':n_threads=4:log_fmt=json:log_path=' + output
            ffmpeg('-i', 'reference.mkv', '-i', distorted, '-filter_complex', graph, '-f', 'null', '-')
            result = json.loads((work / output).read_text())
            assert len(result['frames']) == 12
            assert all(math.isfinite(x['metrics']['vmaf']) for x in result['frames'])
            return result
        models = {}
        for model in sorted((engine / 'models').glob('vmaf_v1*.json')):
            result = score(model)
            models[model.name] = result['pooled_metrics']['vmaf']['mean']
        evidence['checks']['allEightV1ModelsExecute'] = models
        primary = engine / 'models/vmaf_v1.0.16_3d0h.json'
        ident = score(primary, 'reference.mkv', 'identity.json')
        assert ident['pooled_metrics']['vmaf']['mean'] > 99
        assert all(f['metrics']['cambi_full_reference'] == 0 for f in ident['frames'])
        damaged = score(primary)
        assert damaged['pooled_metrics']['vmaf']['mean'] < ident['pooled_metrics']['vmaf']['mean'] - 0.1
        standalone_key = 'cambi_encbd_10_ench_360_encw_640_srch_360_srcw_640'
        for f in damaged['frames']:
            m = f['metrics']
            assert abs(m['cambi_full_reference'] - max(0, m[standalone_key] - m['cambi_source'])) <= 2e-6
        evidence['checks']['identityVMAF'] = ident['pooled_metrics']['vmaf']['mean']
        evidence['checks']['damageVMAF'] = damaged['pooled_metrics']['vmaf']['mean']
        evidence['checks']['cambiKeys'] = [standalone_key, 'cambi_source', 'cambi_full_reference']
        run([engine / 'vmaf', '--reference', 'reference.yuv', '--distorted', 'distorted.yuv', '--width', '640', '--height', '360', '--pixel_format', '420', '--bitdepth', '10', '--model', 'path=model.json:' + options, '--feature', feature.replace('name=cambi:', 'cambi='), '--threads', '4', '--json', '--output', 'upstream.json'], cwd=work)
        upstream = json.loads((work / 'upstream.json').read_text())
        delta = max(abs(a['metrics']['vmaf'] - b['metrics']['vmaf']) for a, b in zip(damaged['frames'], upstream['frames'], strict=True))
        assert delta <= 1e-6, delta
        evidence['checks']['upstreamCLIParityMaxAbsVMAF'] = delta
        # The original encode is 8-bit 320x240, while the compared canvas is 640x360 10-bit.
        ffmpeg('-i', 'distorted.mkv', '-vf', 'scale=320:240,format=yuv420p', '-c:v', 'ffv1', 'small.mkv')
        ffmpeg('-i', 'small.mkv', '-vf', 'scale=640:360:flags=bicubic,format=yuv420p10le', '-c:v', 'ffv1', 'upscaled.mkv')
        options = 'cambi.enc_width=320:cambi.enc_height=240:cambi.enc_bitdepth=8'
        feature = 'name=cambi:full_ref=true:enc_width=320:enc_height=240:enc_bitdepth=8:src_width=640:src_height=360'
        scaled = score(primary, 'upscaled.mkv', 'scaled.json')
        expected = 'cambi_encbd_8_ench_240_encw_320_srch_360_srcw_640'
        assert expected in scaled['frames'][0]['metrics']
        assert any(k.startswith('cambi_hrs_') and 'encbd_8' in k and 'encw_320' in k for k in scaled['frames'][0]['metrics'])
        evidence['checks']['originalEncodeMetadata'] = expected
        def xpsnr(first, second, output):
            ffmpeg('-i', first, '-i', second, '-filter_complex', f'[0:v][1:v]xpsnr=stats_file={output}', '-f', 'null', '-')
            stats = (work / output).read_text()
            assert len(re.findall(r'^n:', stats, re.M)) == 12
            summary = re.search(r'XPSNR average,.*', stats).group(0)
            return stats, summary
        forward, forward_summary = xpsnr('reference.mkv', 'distorted.mkv', 'xpsnr-forward.log')
        reverse, reverse_summary = xpsnr('distorted.mkv', 'reference.mkv', 'xpsnr-reverse.log')
        assert forward_summary != reverse_summary, 'Orientation fixture must distinguish reference from distorted'
        identity, identity_summary = xpsnr('reference.mkv', 'reference.mkv', 'xpsnr-identity.log')
        assert 'inf' in identity_summary
        evidence['checks']['xpsnrOrientation'] = {'referenceFirst': forward_summary, 'distortedFirst': reverse_summary, 'identity': identity_summary}
        evidence['checks']['boundedThreads'] = 4
    # Avoid transient directory noise in checked-in evidence.
    evidence['commands'] = [[arg.replace(td, '<temporary-directory>') for arg in cmd] for cmd in evidence['commands']]
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence['checks'], indent=2))

if __name__ == '__main__':
    main()
