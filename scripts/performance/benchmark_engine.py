#!/usr/bin/env python3
"""macOS per-child wall/CPU/RSS/progress benchmark; no third-party Python modules."""
import argparse, hashlib, json, os, pathlib, subprocess, threading, time


def output(args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def measure(argv, cancel_after=None):
    started = time.monotonic()
    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    progress, errors = [], []
    def drain(pipe, dest, progress_pipe=False):
        for line in iter(pipe.readline, b''):
            text = line.decode(errors='replace').strip()
            if progress_pipe and text.startswith('frame='):
                try:
                    if int(text[6:].strip()) > 0:
                        dest.append({'seconds': time.monotonic()-started, 'frame': int(text[6:].strip())})
                except ValueError:
                    pass
            elif not progress_pipe:
                dest.append(text)
        pipe.close()
    readers = [threading.Thread(target=drain, args=(proc.stdout, progress, True)), threading.Thread(target=drain, args=(proc.stderr, errors))]
    for reader in readers: reader.start()
    cancelled = []
    def cancel():
        time.sleep(cancel_after)
        try:
            cancelled.append(time.monotonic())
            proc.terminate()
        except ProcessLookupError: pass
    if cancel_after: threading.Thread(target=cancel, daemon=True).start()
    _, status, usage = os.wait4(proc.pid, 0)
    ended = time.monotonic()
    proc.returncode = os.waitstatus_to_exitcode(status)
    for reader in readers: reader.join()
    wall = ended-started
    return {'argv': argv, 'returncode': proc.returncode, 'wall_seconds': wall,
            'cpu_user_seconds': usage.ru_utime, 'cpu_system_seconds': usage.ru_stime,
            'average_cpu_percent': 100*(usage.ru_utime+usage.ru_stime)/wall,
            'peak_rss_bytes': usage.ru_maxrss,
            'first_positive_progress_seconds': progress[0]['seconds'] if progress else None,
            'last_progress_frame': progress[-1]['frame'] if progress else None,
            'cancel_to_exit_seconds': ended-cancelled[0] if cancelled else None,
            'stderr_tail': errors[-8:]}


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--engine', required=True)
    ap.add_argument('--generator', default='/opt/homebrew/bin/ffmpeg')
    ap.add_argument('--work', default='/tmp/bettervmaf-performance/matrix')
    ap.add_argument('--model', default='VMAF/Resources/Models/vmaf_v0.6.1.json')
    ap.add_argument('--threads', type=int, default=4)
    ap.add_argument('--decode-threads', type=int, default=4)
    ap.add_argument('--output', required=True)
    ap.add_argument('--generate-only', action='store_true')
    ap.add_argument('--parity', action='store_true')
    ap.add_argument('--standard', action='store_true')
    ap.add_argument('--metric-only', action='store_true')
    ap.add_argument('--label', required=True)
    args=ap.parse_args()
    engine=str(pathlib.Path(args.engine).resolve()); model=str(pathlib.Path(args.model).resolve())
    work=pathlib.Path(args.work); work.mkdir(parents=True, exist_ok=True)
    report={'label': args.label, 'recorded_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'hardware': output(['sysctl','-n','machdep.cpu.brand_string']),
            'memory_bytes': int(output(['sysctl','-n','hw.memsize'])), 'os':output(['sw_vers']),
            'engine_version':output([engine,'-version']), 'engine_sha256':hashlib.sha256(pathlib.Path(engine).read_bytes()).hexdigest(),
            'model_sha256':hashlib.sha256(pathlib.Path(model).read_bytes()).hexdigest(),
            'threads':args.threads, 'decode_threads':args.decode_threads, 'measurements':[], 'notes':['2 second synthetic testsrc2 clips; repeated identical source/encode input isolates pipeline overhead, not realism.', 'First positive progress is not first metric or UI result. Metric JSON is available at process completion.', 'CPU percent is child CPU seconds / wall; RSS is wait4 ru_maxrss bytes on Darwin.', 'No GPU counters or joules inferred from CPU. External concurrent jobs may affect wall time.']}
    for width,height in [(1920,1080),(3840,2160)]:
        for bitdepth in [8,10]:
            for fps in [24,60]:
                name=f'{height}p-{bitdepth}bit-{fps}fps'; path=work/(name+'.mp4')
                pix='yuv420p' if bitdepth==8 else 'yuv420p10le'
                generation=[args.generator,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i',f'testsrc2=size={width}x{height}:rate={fps}:duration=2','-vf',f'format={pix}','-c:v','libx264' if bitdepth==8 else 'libx265','-preset','ultrafast','-crf','18','-threads','4']
                if bitdepth==10: generation += ['-x265-params','pools=4:frame-threads=2:log-level=error','-tag:v','hvc1']
                generation += ['-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv',str(path)]
                if not path.exists(): subprocess.run(generation, check=True)
                if args.generate_only: continue
                common=[engine,'-hide_banner','-loglevel','error','-nostdin','-progress','pipe:1','-stats_period','0.05']
                decode=common+['-threads',str(args.decode_threads),'-i',str(path),'-an','-f','null','-']
                row={'case':name,'frames':fps*2,'input_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'generation_argv':generation,'decode':measure(decode)}
                logfile=work/(name+'-'+args.label+'.json')
                graph=f'[0:v]setpts=PTS-STARTPTS[r];[1:v]setpts=PTS-STARTPTS[d];[d][r]libvmaf=model=path={model}:log_fmt=json:log_path={logfile}:n_threads={args.threads}:eof_action=endall:shortest=1:repeatlast=0'
                if args.standard:
                    active_model=model.replace('vmaf_v1.0.16_', 'vmaf_v1.0.16_hfr_') if fps>=45 else model
                    normalization='scale=w=iw:h=ih:flags=bicubic+accurate_rnd+bitexact:in_range=limited:out_range=limited:in_color_matrix=bt709:out_color_matrix=bt709:in_h_chr_pos=0:in_v_chr_pos=128:out_h_chr_pos=0:out_v_chr_pos=128,format=yuv420p10le,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709,settb=AVTB,setpts=PTS-STARTPTS'
                    graph=f"[0:v]{normalization},split=2[r][xr];[1:v]{normalization},split=2[d][xd];[d][r]libvmaf=model='path={active_model}\\:cambi.enc_width={width}\\:cambi.enc_height={height}\\:cambi.enc_bitdepth={bitdepth}':feature='name=cambi\\:full_ref=true\\:enc_width={width}\\:enc_height={height}\\:enc_bitdepth={bitdepth}\\:src_width={width}\\:src_height={height}':log_fmt=json:log_path={logfile}:n_threads={args.threads}:eof_action=endall:shortest=1:repeatlast=0:ts_sync_mode=nearest[vm];[xr][xd]xpsnr=stats_file={work/name}.xpsnr:shortest=1:repeatlast=0:eof_action=endall:ts_sync_mode=nearest[xp]"
                metric=common+['-threads',str(args.decode_threads),'-i',str(path),'-threads',str(args.decode_threads),'-i',str(path),'-filter_complex_threads',str(args.threads),'-lavfi',graph,'-an','-f','null','-']
                if args.standard: metric=metric[:-4]+['-map','[vm]','-map','[xp]']+metric[-4:]
                if args.standard:
                    row['selected_model_sha256']=hashlib.sha256(pathlib.Path(active_model).read_bytes()).hexdigest()
                    row['selected_model_path']=active_model
                row['decode_and_vmaf']=measure(metric)
                if args.metric_only:
                    raw=work/(name+'.raw')
                    rawgen=[engine,'-hide_banner','-loglevel','error','-nostdin','-y','-i',str(path),'-pix_fmt',pix,'-f','rawvideo',str(raw)]
                    subprocess.run(rawgen,check=True)
                    rawinput=['-f','rawvideo','-pixel_format',pix,'-video_size',f'{width}x{height}','-framerate',str(fps),'-i',str(raw)]
                    rawargv=common+rawinput+rawinput+['-filter_complex_threads',str(args.threads),'-lavfi',graph]
                    if args.standard: rawargv+=['-map','[vm]','-map','[xp]']
                    rawargv+=['-an','-f','null','-']
                    row['raw_generation_argv']=rawgen
                    row['decode_free_metric']=measure(rawargv)
                    row['decode_free_metric']['frames_per_second']=fps*2/row['decode_free_metric']['wall_seconds']
                    row['decode_free_metric']['note']='Predecoded rawvideo inputs remove codec decoding; includes cached file reads, metric filtering, process startup and JSON flush.'
                    raw.unlink()
                row['decode']['frames_per_second']=fps*2/row['decode']['wall_seconds']
                row['decode_and_vmaf']['frames_per_second']=fps*2/row['decode_and_vmaf']['wall_seconds']
                if logfile.exists():
                    j=json.loads(logfile.read_text()); row['libvmaf_reported_fps']=j.get('fps'); row['vmaf_mean']=j.get('pooled_metrics',{}).get('vmaf',{}).get('mean')
                if args.parity:
                    hashes={}
                    for method in ['software','videotoolbox']:
                        dest=work/(name+'-'+method+'.framemd5')
                        argv=[engine,'-hide_banner','-loglevel','error','-nostdin','-y']
                        if method=='videotoolbox': argv+=['-hwaccel','videotoolbox']
                        argv+=['-i',str(path),'-pix_fmt',pix,'-f','framemd5',str(dest)]
                        p=subprocess.run(argv,capture_output=True,text=True)
                        values=[s.split(',')[-1].strip() for s in dest.read_text().splitlines() if not s.startswith('#')] if dest.exists() else []
                        hashes[method]={'argv':argv,'returncode':p.returncode,'hashes':values,'stderr':p.stderr[-1000:]}
                    row['decode_parity']={'identical_frames':all(method['returncode']==0 and len(method['hashes'])==fps*2 for method in hashes.values()) and hashes['software']['hashes']==hashes['videotoolbox']['hashes'], 'methods':hashes}
                report['measurements'].append(row)
                pathlib.Path(args.output).write_text(json.dumps(report,indent=2)+'\n')
                print(name, 'decode',round(row['decode']['frames_per_second'],1),'vmaf',round(row['decode_and_vmaf']['frames_per_second'],1),flush=True)
    if not args.generate_only:
        path=work/'2160p-10bit-60fps.mp4'
        cancel=[engine,'-hide_banner','-loglevel','error','-nostdin','-progress','pipe:1','-stream_loop','-1','-i',str(path),'-f','null','-']
        report['cancellation_decode_process']=measure(cancel,cancel_after=1)
        pathlib.Path(args.output).write_text(json.dumps(report,indent=2)+'\n')
        failed=[r['case'] for r in report['measurements'] if r['decode']['returncode'] != 0 or r['decode_and_vmaf']['returncode'] != 0 or r.get('decode_free_metric',{}).get('returncode',0) != 0]
        if failed: raise SystemExit('Benchmark failed: '+', '.join(failed))
        if args.parity and any(not row['decode_parity']['identical_frames'] for row in report['measurements']):
            raise SystemExit('Software/hardware decode parity failed')

if __name__=='__main__': main()
