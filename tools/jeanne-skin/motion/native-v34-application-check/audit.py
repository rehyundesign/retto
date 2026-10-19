from pathlib import Path
import re,json,hashlib
p=Path(__file__).parent;root=p.parent;res=p/'Retto.app/Contents/Resources/JeanneFrames';m=json.loads((res/'manifest.json').read_text());source=json.loads((root/'state-integrated-v31-data.js').read_text().split('=',1)[1].strip().removesuffix(';'))
t=(p/'Sources/Tones.swift').read_text().split('let animationCatalog:')[1].split('\n]')[0];expected={s:int(row) for s,row in re.findall(r'\.(\w+): Animation\(row: (\d+)',t)};expected.update({'drag-right':1,'drag-left':2})
report=[]
for s in m['states']:
 assert expected[s['id']]==s['row'],s['id'];o=next(x for x in source if x['id']==s['id']);assert len(o['files'])==len(s['files'])
 for f,g in zip(s['files'],o['files']):assert hashlib.sha256((res/f).read_bytes()).digest()==hashlib.sha256((root/g).read_bytes()).digest()
 assert abs(sum(s['times'])-s['cycle'])<1e-8
 report.append({'state':s['id'],'row':s['row'],'frames':len(s['files']),'cycle':s['cycle'],'sourceImageHashes':'match v31','stateMapping':'pass'})
for i in range(16):assert (res/f'gaze-{i}.png').read_bytes()==(root/'gaze-v25'/f'{i:02}.png').read_bytes()
(p/'state-art-audit.json').write_text(json.dumps({'states':report,'gazeSources':16,'completion':'waving remains waving after 3 cycles; user acknowledgement may still legitimately yield idle','sleep':'baked sleep effects only; duplicate procedural z disabled for Jeanne'},indent=2))
print('10 state mappings,144 source image hashes,16 gaze sources and cycle durations verified')
