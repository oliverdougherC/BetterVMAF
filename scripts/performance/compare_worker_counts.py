#!/usr/bin/env python3
"""Paired4/7-worker Standard metric-process trials on the exact UI workload."""
from benchmark_engine import measure
import hashlib,json,pathlib,time

repo=pathlib.Path(__file__).resolve().parents[2]
engine=repo/'VMAF/Resources/engine/ffmpeg'
model=repo/'VMAF/Resources/engine/models/vmaf_v1.0.16_hfr_3d0h.json'
work=pathlib.Path('/tmp/bettervmaf-performance/ui-workload')
source=work/'source-4k60.mp4';encode=work/'encode-4k60.mp4'
normalization='scale=w=iw:h=ih:flags=bicubic+accurate_rnd+bitexact:in_range=limited:out_range=limited:in_color_matrix=bt709:out_color_matrix=bt709:in_h_chr_pos=0:in_v_chr_pos=128:out_h_chr_pos=0:out_v_chr_pos=128,format=yuv420p10le,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709,settb=AVTB,setpts=PTS-STARTPTS'
eof='shortest=1:repeatlast=0:eof_action=endall:ts_sync_mode=nearest'
report={'recorded_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'engine_sha256':hashlib.sha256(engine.read_bytes()).hexdigest(),'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'encode_sha256':hashlib.sha256(encode.read_bytes()).hexdigest(),'note':'ABAB trials on active Mac; metric process only, excludes app preflight/signatures/UI. Same pinned HFR model, normalization, input files and coverage.','trials':[]}
for index,threads in enumerate([4,7,4,7]):
 logfile=work/f'workers-{threads}-{index}.json'
 graph=f"[0:v]{normalization},split=2[r][xr];[1:v]{normalization},split=2[d][xd];[d][r]libvmaf=model='path={model}\\:cambi.enc_width=3840\\:cambi.enc_height=2160\\:cambi.enc_bitdepth=8':feature='name=cambi\\:full_ref=true\\:enc_width=3840\\:enc_height=2160\\:enc_bitdepth=8\\:src_width=3840\\:src_height=2160':n_threads={threads}:log_fmt=json:log_path={logfile}:{eof}[vm];[xr][xd]xpsnr=stats_file={work}/workers-{index}.xpsnr:{eof}[xp]"
 argv=[str(engine),'-hide_banner','-nostdin','-loglevel','error','-progress','pipe:1','-stats_period','0.05','-filter_complex_threads',str(threads),'-threads',str(threads),'-noautorotate','-i',str(source),'-threads',str(threads),'-noautorotate','-i',str(encode),'-filter_complex',graph,'-map','[vm]','-map','[xp]','-fps_mode','passthrough','-f','null','-']
 trial=measure(argv);trial['threads']=threads;trial['frames_per_second']=240/trial['wall_seconds']
 if trial['returncode']!=0:raise SystemExit(trial['stderr_tail'])
 result=json.loads(logfile.read_text());trial['frames']=len(result['frames']);trial['vmaf_mean']=result['pooled_metrics']['vmaf']['mean'];assert trial['frames']==240
 report['trials'].append(trial)
 (repo/'docs/evidence/performance-worker-counts.json').write_text(json.dumps(report,indent=2)+'\n')
 print(threads,round(trial['frames_per_second'],2),round(trial['peak_rss_bytes']/1048576),trial['vmaf_mean'],flush=True)
assert max(t['vmaf_mean'] for t in report['trials'])-min(t['vmaf_mean'] for t in report['trials'])<1e-6
report['metric_cancellation_trials']=[]
for threads in [4,7]:
    cancel_argv=argv.copy()
    for index,part in enumerate(cancel_argv):
        if part in ['-threads','-filter_complex_threads']:
            cancel_argv[index+1]=str(threads)
        if part=='-filter_complex':
            cancel_argv[index+1]=graph.replace('n_threads=7',f'n_threads={threads}').replace(str(logfile),str(work/f'cancel-workers-{threads}.json')).replace('workers-3.xpsnr',f'cancel-workers-{threads}.xpsnr')
    trial=measure(cancel_argv,cancel_after=1);trial['threads']=threads
    report['metric_cancellation_trials'].append(trial)
(repo/'docs/evidence/performance-worker-counts.json').write_text(json.dumps(report,indent=2)+'\n')
