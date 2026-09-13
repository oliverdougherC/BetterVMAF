#!/usr/bin/env python3
"""Capture a caller-coordinated native UI workload without driving the UI."""
import argparse, datetime, json, pathlib, signal, subprocess

ap=argparse.ArgumentParser()
ap.add_argument('--pid',type=int,required=True)
ap.add_argument('--seconds',type=int,default=45)
ap.add_argument('--name',default='analysis-export')
ap.add_argument('--template',default='Animation Hitches')
ap.add_argument('--directory',default='/tmp/bettervmaf-performance/traces')
args=ap.parse_args()
root=pathlib.Path(args.directory);root.mkdir(parents=True,exist_ok=True)
trace=root/(args.name+'.trace')
if trace.exists(): raise SystemExit(f'Refusing to overwrite existing trace: {trace}')
argv=['xcrun','xctrace','record','--template',args.template,'--attach',str(args.pid),'--time-limit',f'{args.seconds}s','--output',str(trace),'--no-prompt']
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
print('Recording requested: '+started,flush=True)
proc=subprocess.Popen(argv,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
stalled=False
try:
    stdout,stderr=proc.communicate(timeout=args.seconds+60)
except subprocess.TimeoutExpired:
    stalled=True
    proc.send_signal(signal.SIGINT)
    try:
        stdout,stderr=proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            stdout,stderr=proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout,stderr=proc.communicate()
record={'requested_utc':started,'argv':argv,'status':proc.returncode,'stalled':stalled,'stdout':stdout,'stderr':stderr,'trace_path':str(trace),'note':'Capture does not create or drive workload. Record the exact human/automation interactions and interval separately; no idle trace is responsiveness evidence.'}
if proc.returncode==0:
 toc=root/(args.name+'-toc.xml')
 p=subprocess.run(['xcrun','xctrace','export','--input',str(trace),'--toc','--output',str(toc)],text=True,capture_output=True)
 record['toc_export']={'status':p.returncode,'path':str(toc),'stdout':p.stdout,'stderr':p.stderr}
pathlib.Path('docs/evidence/performance-ui-'+args.name+'.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
raise SystemExit(proc.returncode)
