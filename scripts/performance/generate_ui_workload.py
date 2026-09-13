#!/usr/bin/env python3
"""Generate a tagged playable 4K60 four-second comparison outside Git."""
import hashlib, json, pathlib, subprocess

root=pathlib.Path('/tmp/bettervmaf-performance/ui-workload')
root.mkdir(parents=True,exist_ok=True)
ffmpeg='/opt/homebrew/bin/ffmpeg'
source=root/'source-4k60.mp4'; encode=root/'encode-4k60.mp4'
color=['-color_range','tv','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-chroma_sample_location','left']
commands=[
 [ffmpeg,'-hide_banner','-loglevel','error','-nostdin','-y','-f','lavfi','-i','testsrc2=size=3840x2160:rate=60:duration=4','-c:v','libx264','-preset','ultrafast','-crf','12','-pix_fmt','yuv420p','-threads','4','-g','120','-bsf:v','h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0:chroma_sample_loc_type=0']+color+['-movflags','+faststart',str(source)],
 [ffmpeg,'-hide_banner','-loglevel','error','-nostdin','-y','-i',str(source),'-c:v','libx264','-preset','fast','-crf','36','-pix_fmt','yuv420p','-threads','4','-g','120','-bsf:v','h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0:chroma_sample_loc_type=0']+color+['-movflags','+faststart',str(encode)]
]
for command in commands: subprocess.run(command,check=True)
report={'purpose':'Playable native UI workload, four seconds3840x2160at60fps;240frames. Not a conformance expected-score fixture.','rights':'FFmpeg-generated synthetic testsrc2; generation recipe provided under repository MIT license.','generator_version':subprocess.check_output([ffmpeg,'-version'],text=True).splitlines()[0],'commands':commands,'files':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in [source,encode]]}
pathlib.Path('docs/evidence/performance-ui-workload.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['files'],indent=2))
